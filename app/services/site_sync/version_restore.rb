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

      # The same rule the page shows: only a file's latest change can be
      # undone. An older one has been restored or changed again since.
      states = row_states([ { changes: rows } ])
      undoable = rows.select { |c| states[c[:id]] == :undo }
      raise Error, "Those files have changed since. Undo the latest change to each one instead." if undoable.empty?

      new(undoable.to_h { |c| [ c[:path], c[:before_sha] ] }).call
    end

    # The whole site as it was just after `event_id`: only paths that differ
    # from it now are written.
    def self.point(event_id)
      new(plan_for_point(event_id)).call
    end

    # What restoring to `event_id` would change, as { path => sha or nil }.
    # Paths already matching are left out, so this is also the preview.
    # `hashes` is shared between calls on one page, so each file on disk is
    # read at most once however many restore points are checked.
    def self.plan_for_point(event_id, hashes: {})
      Versions.state_after(event_id.to_i).reject { |rel, sha| matches?(rel, sha, hashes: hashes) }
    end

    # Whether restoring to `event_id` would write anything: something differs
    # and there's a saved copy (or nothing) to put in its place.
    def self.point_restorable?(event_id, hashes: {})
      plan_for_point(event_id, hashes: hashes).any? { |_, sha| sha.nil? || Versions.object?(sha) }
    end

    # Whether the file on disk is already that version (nil = absent). With
    # the version's size, a file of another size is settled without reading it.
    def self.matches?(rel, sha, size: nil, hashes: {})
      abs = File.join(RoeSitePaths::SITE_PATH, rel)
      return !File.exist?(abs) if sha.nil?
      return false unless File.file?(abs)
      return false if size && File.size(abs) != size

      hashes[rel] ||= Digest::SHA256.file(abs).hexdigest
      hashes[rel] == sha
    end

    # How each change in `events` can be acted on in the history:
    #   :undo         the latest change to its file, with a saved copy to go back to
    #   :restored     a restore came after it
    #   :changed      a later sync changed the file again
    #   :in_place     the file is already the version before this change
    #   :no_copy      no saved copy of the version before
    # Only the latest change to a file can be undone, so a file can't be
    # restored twice from two places, and a restore is undone from its own
    # entry.
    def self.row_states(events, hashes: {})
      changes = events.flat_map { |e| e[:changes] }
      return {} if changes.empty?

      later = Versions.changes_after(changes.map { |c| c[:path] }.uniq, changes.map { |c| c[:id] }.min)
                      .group_by { |c| c[:path] }
      changes.to_h do |c|
        following = later[c[:path]].to_a.find { |l| l[:id] > c[:id] }
        state =
          if following
            following[:kind] == "restore" ? :restored : :changed
          elsif c[:before_sha] && !Versions.object?(c[:before_sha])
            :no_copy
          elsif matches?(c[:path], c[:before_sha], size: c[:before_size], hashes: hashes)
            :in_place
          else
            :undo
          end
        [ c[:id], state ]
      end
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
