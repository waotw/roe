# frozen_string_literal: true

module SiteSync
  # Take specific files back out of the snapshot a sync took before it wrote.
  #
  # Recovering from a bad sync by hand means diffing a snapshot against /site,
  # working out which differences were the sync's doing, copying those back and
  # reconciling the database. That's a slow, error-prone afternoon, and the
  # history already knows every path involved. This turns it into picking the
  # files you want back.
  #
  # Only ever restores INTO local. The snapshot is of /site as it stood before
  # the sync touched it, so it can answer "what did this do to my machine" and
  # nothing about what it did to live — see History for the direction split.
  class HistoryRestore
    class Error < StandardError; end

    Result = Struct.new(:restored, :skipped, :snapshot, keyword_init: true) do
      def any? = restored.any?
    end

    def self.call(snapshot_name:, paths:) = new(snapshot_name, paths).call

    # What state each path is in relative to the snapshot, so the page can say
    # what's already been put back. Without it every row looks identical
    # whether or not you've restored it, and on a long list there's no way to
    # tell what you've already done.
    #
    #   :restored    — the file on disk matches the snapshot's copy
    #   :restorable  — it differs, or it isn't there at all
    #   :unavailable — the snapshot doesn't have it, so there's nothing to take
    #
    # "Restored" is really "matches the pre-sync version" — a file could match
    # because you restored it or because the sync's change was later undone
    # another way. Either way there's nothing left to take from here, which is
    # what the row is telling you.
    def self.states(snapshot_name:, paths:)
      new(snapshot_name, paths).states
    end

    def states
      return {} unless snapshot_dir

      @paths.index_with do |rel|
        source = safe_source(rel)
        next :unavailable if source.nil?

        target = File.join(RoeSitePaths::SITE_PATH, rel)
        File.file?(target) && same_file?(source, target) ? :restored : :restorable
      end
    end

    def initialize(snapshot_name, paths)
      @snapshot_name = snapshot_name.to_s
      @paths = Array(paths).map(&:to_s).reject(&:blank?).uniq
    end

    def call
      raise Error, "No files selected." if @paths.empty?
      raise Error, "That restore point no longer exists." unless snapshot_dir

      # Restoring overwrites, so it gets the same safety net a sync gets: a
      # snapshot of the current state first. Undoing a restore matters as much
      # as undoing the sync that prompted it.
      BackupManager.create

      restored, skipped = [], []
      @paths.each do |rel|
        source = safe_source(rel)
        next skipped << rel if source.nil?

        target = File.join(RoeSitePaths::SITE_PATH, rel)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(source, target, preserve: true)
        restored << rel
      end

      # rsync moves files; the Post/Page/Product/Medium rows still describe the
      # state before this. Without it a restored file is on disk and invisible.
      ContentSync.sync_all if restored.any?
      Checker.clear_cache

      Rails.logger.info "[SiteSync::HistoryRestore] restored #{restored.size} file(s) from #{@snapshot_name}"
      Result.new(restored: restored.sort, skipped: skipped.sort, snapshot: @snapshot_name)
    end

    private

    # The snapshot directory, or nil. Matched against the real listing rather
    # than built from the parameter, so a crafted name can't walk out of the
    # backups directory.
    def snapshot_dir
      return @snapshot_dir if defined?(@snapshot_dir)

      @snapshot_dir = begin
        root = BackupPaths.local
        dir  = File.join(root, @snapshot_name)
        valid = @snapshot_name.match?(BackupManager::SNAPSHOT_NAME_RE) && Dir.exist?(dir)
        valid ? dir : nil
      end
    end

    # Size first, bytes only when it can't settle it — a media directory would
    # otherwise digest hundreds of megabytes on every page render.
    def same_file?(a, b)
      return false unless File.size(a) == File.size(b)

      Digest::SHA256.file(a).hexdigest == Digest::SHA256.file(b).hexdigest
    end

    # A readable file inside this snapshot that Site Sync is allowed to write.
    #
    # Three ways to say no: it escapes the snapshot (traversal), it isn't
    # there, or it's a path the ledger excludes — system/secrets/ above all,
    # which must never be written from anything but its own install.
    def safe_source(rel)
      return nil if rel.include?("\0") || Ledger.excluded?(rel)

      full = File.expand_path(File.join(snapshot_dir, rel))
      return nil unless full.start_with?(File.expand_path(snapshot_dir) + File::SEPARATOR)
      return nil unless File.file?(full)

      full
    end
  end
end
