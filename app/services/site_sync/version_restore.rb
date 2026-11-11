# frozen_string_literal: true

module SiteSync
  # Put files back from the version store (SiteSync::Versions): the version a
  # change replaced, or the whole site as it was just after a sync.
  #
  # Always writes into local /site, with a new modified time, so the next sync
  # sees a local change and carries it to live. That's how a restore reaches
  # live without any way to write there directly.
  #
  # A restore is itself recorded, with what it replaced saved first, so it can
  # be undone the same way.
  class VersionRestore
    class Error < StandardError; end

    Result = Struct.new(:restored, :removed, :skipped, keyword_init: true) do
      def count = restored.size + removed.size
    end

    # Undo these changes: each path goes back to the version its change replaced
    # (absent, for a file the change added).
    def self.changes(ids)
      ids = Array(ids).map(&:to_i).uniq
      raise Error, "No files selected." if ids.empty?

      rows = Versions.changes_by_id(ids)
      raise Error, "Those changes are no longer in the history." if rows.empty?

      new(rows.to_h { |c| [ c[:path], c[:before_sha] ] }).call
    end

    # The whole site as it was just after `event_id`: only paths that differ
    # from it now are written.
    def self.point(event_id)
      new(plan_for_point(event_id)).call
    end

    # What restoring to `event_id` would change, as { path => sha or nil }.
    # Paths already matching are left out, so this is also the preview.
    def self.plan_for_point(event_id)
      Versions.state_after(event_id.to_i).reject { |rel, sha| matches?(rel, sha) }
    end

    # Whether the file on disk is already that version (nil = absent). With
    # the version's size, a file of another size is settled without reading it.
    def self.matches?(rel, sha, size: nil)
      abs = File.join(RoeSitePaths::SITE_PATH, rel)
      return !File.exist?(abs) if sha.nil?
      return false unless File.file?(abs)
      return false if size && File.size(abs) != size

      Digest::SHA256.file(abs).hexdigest == sha
    end

    def initialize(targets)
      @targets = targets.select { |rel, _| writable?(rel) }
      @skipped = (targets.keys - @targets.keys)
    end

    def call
      todo, missing = @targets.partition { |rel, sha| sha.nil? || Versions.object?(sha) }
      @skipped += missing.map(&:first)
      todo = todo.reject { |rel, sha| self.class.matches?(rel, sha) }
      return Result.new(restored: [], removed: [], skipped: @skipped.sort) if todo.empty?

      # What's there now is saved before it's replaced. If it can't be, nothing
      # is written.
      recorder = Versions::Recorder.new
      removals = todo.select { |_, sha| sha.nil? }.map(&:first)
      recorder.save_local!(todo.map(&:first), deleted: removals)

      restored, removed = [], []
      todo.each do |rel, sha|
        abs = File.join(RoeSitePaths::SITE_PATH, rel)
        if sha.nil?
          File.delete(abs) if File.exist?(abs)
          removed << rel
        else
          FileUtils.mkdir_p(File.dirname(abs))
          tmp = "#{abs}.roe-restore-#{SecureRandom.hex(4)}"
          FileUtils.cp(Versions.object_path(sha), tmp)
          File.rename(tmp, abs)
          restored << rel
        end
      end

      recorder.finish!(kind: :restore, outcome: :completed)
      ContentSync.sync_all
      Checker.clear_cache
      Rails.logger.info "[SiteSync::VersionRestore] restored #{restored.size}, removed #{removed.size}, skipped #{@skipped.size}"
      Result.new(restored: restored.sort, removed: removed.sort, skipped: @skipped.sort)
    end

    private

    # A plain relative path inside /site that Site Sync is allowed to write —
    # never system/secrets/ or anything else the ledger keeps out.
    def writable?(rel)
      return false if rel.blank? || rel.include?("\0") || rel.start_with?("/")
      return false if Ledger.excluded?(rel)

      site = File.expand_path(RoeSitePaths::SITE_PATH)
      File.expand_path(File.join(site, rel)).start_with?(site + File::SEPARATOR)
    end
  end
end
