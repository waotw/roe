module SiteSync
  # Tracks the "last known synced" state of /site by recording a manifest
  # of every tracked file (size + mtime) at .sync-state.json. Diffing the
  # current filesystem against the recorded manifest is how local drift
  # gets detected for the admin banner.
  #
  # Size + mtime is what rsync uses by default — so what we report as
  # "changed" matches what an actual rsync would push.
  class Ledger
    LEDGER_FILENAME = ".sync-state.json"

    # Top-level subdirs of /site we never include in the ledger or backups:
    #   - db/        managed by RoeUpdater::BackupManager (own backup system)
    #   - .git/      user's optional git repo for /site, not our concern
    #   - .sync-backups/ defensive — in case anyone parks site backups inside
    EXCLUDED_DIRS = %w[db .git .sync-backups].freeze

    # Paths (nested) excluded as whole subtrees, matched as path
    # prefixes from /site's root:
    #   - system/secrets/   per-install encryption keys (master.key +
    #                       credentials.yml.enc). Kept out of SiteSync
    #                       so dev and prod each have their own keys
    #                       and an accidental sync can never overwrite
    #                       the production key with a dev one.
    #   - media/images/variants/  generated image renditions. They're a
    #                       rebuildable cache — each side generates them
    #                       on-demand from the originals — so syncing them
    #                       is pure noise: any variant lazily created on
    #                       one side reads as drift against the other.
    #                       BackupManager already excludes them for the
    #                       same reason.
    EXCLUDED_PATHS = %w[system/secrets media/images/variants].freeze

    # Filenames excluded wherever they appear in the tree:
    #   - .DS_Store       macOS noise that appears in every browsed dir
    #   - .sync-state.json the ledger itself; otherwise the ledger's mtime
    #                     bumps every time we write it and we'd flap drift
    #   - .last_deploy.yml tracks local deploy state, environment-specific
    EXCLUDED_FILES = %w[.DS_Store .sync-state.json .last_deploy.yml].freeze

    class << self
      def current
        new.current_manifest
      end

      def recorded
        new.recorded_manifest
      end

      def write_current!
        new.write_current!
      end

      def write_manifest!(manifest)
        new.write_manifest!(manifest)
      end

      # Compare two file-hashes, returning the file-level diff. Sorted
      # lists so the UI is stable across reloads.
      def diff(current_files, recorded_files)
        recorded_files ||= {}
        added = current_files.keys - recorded_files.keys
        deleted = recorded_files.keys - current_files.keys
        common = current_files.keys & recorded_files.keys

        modified = common.select do |path|
          c = current_files[path]
          r = recorded_files[path]
          c["size"] != r["size"] || c["mtime"] != r["mtime"]
        end

        { modified: modified.sort, added: added.sort, deleted: deleted.sort }
      end

      # Stable, *canonical* hash over a manifest. Keys are sorted before
      # JSON-encoding so two filesystems holding the same content
      # produce the same hash — Dir.glob returns entries in
      # filesystem-dependent order (macOS APFS vs Linux ext4 inside a
      # container will differ), and an unsorted Hash#to_json embeds
      # that order. Without this sort, identical /site trees on dev
      # and live could fingerprint differently and the cross-env
      # exchange would falsely report drift.
      #
      # Sort applies to the top-level path map; the inner {size, mtime}
      # hashes always have a fixed key order (built that way in
      # current_manifest) so they don't need separate canonicalization.
      def fingerprint_of(manifest)
        sorted = manifest.sort.to_h
        Digest::SHA256.hexdigest(sorted.to_json)
      end

      # Convenience: compute the fingerprint of an arbitrary directory
      # by walking it like /site. Used to fingerprint backup snapshots
      # at create time (and to check the live /site state for active-
      # backup detection).
      def fingerprint_for(path)
        fingerprint_of(new(site_path: path).current_manifest)
      end

      # Whether a /site-relative path is excluded from tracking/transfer.
      # Public (and the single source of truth) so the tar unpacker can
      # refuse to write excluded paths — e.g. system/secrets/ — from an
      # untrusted uploaded archive.
      def excluded?(relative_path)
        parts = relative_path.split("/")
        return true if EXCLUDED_DIRS.include?(parts.first)
        return true if EXCLUDED_FILES.include?(parts.last)

        EXCLUDED_PATHS.any? { |p| relative_path == p || relative_path.start_with?("#{p}/") }
      end
    end

    def initialize(site_path: RoeSitePaths::SITE_PATH)
      @site_path = site_path
    end

    def ledger_path
      File.join(@site_path, LEDGER_FILENAME)
    end

    def current_manifest
      return {} unless Dir.exist?(@site_path)

      manifest = {}
      prefix = @site_path.end_with?("/") ? @site_path : "#{@site_path}/"

      Dir.glob(File.join(@site_path, "**", "*"), File::FNM_DOTMATCH).each do |path|
        next if File.directory?(path)
        next if File.symlink?(path)

        relative = path.sub(/\A#{Regexp.escape(prefix)}/, "")
        next if excluded?(relative)

        # File can vanish between Dir.glob enumerating it and us
        # stat'ing it — common with rsync's atomic write (write to
        # .tmp, rename) or image-variant temp files like
        # `.foo.jpeg.aB3xZq`. Skip these gracefully rather than
        # crashing the whole drift check.
        begin
          stat = File.stat(path)
        rescue Errno::ENOENT
          next
        end

        manifest[relative] = {
          "size"  => stat.size,
          "mtime" => stat.mtime.to_i
        }
      end

      manifest
    end

    def recorded_manifest
      return nil unless File.exist?(ledger_path)
      JSON.parse(File.read(ledger_path))
    rescue JSON::ParserError => e
      Rails.logger.error "[SiteSync::Ledger] Corrupted ledger at #{ledger_path}: #{e.message}"
      nil
    end

    def write_current!
      write_manifest!(current_manifest)
    end

    # Lower-level write: persist a pre-computed manifest as the new
    # baseline. Used by callers that already have the manifest in
    # hand (e.g. SiteSync::Checker after computing drift) so we don't
    # walk /site twice in a row.
    def write_manifest!(manifest)
      data = {
        "version"     => Time.now.utc.iso8601,
        "fingerprint" => self.class.fingerprint_of(manifest),
        "env"         => Rails.env,
        "files"       => manifest
      }
      File.write(ledger_path, JSON.pretty_generate(data))
      data
    end

    private

    def excluded?(relative_path)
      self.class.excluded?(relative_path)
    end
  end
end
