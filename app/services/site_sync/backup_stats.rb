# frozen_string_literal: true

module SiteSync
  # How many backups there are and what they actually occupy on disk.
  #
  # Backups are rsync snapshots with hard links, so most files across snapshots
  # share one inode — only what changed between them is stored twice. Adding up
  # File.size counts every link separately and overstates the total wildly: on
  # one install, 4,869 files across 17 backups summed to 3.07 GB while the disk
  # held 253.6 MB. That's the number Finder reports too, which is why it looks
  # wrong there.
  #
  # So: count each inode once, and use allocated blocks rather than apparent
  # size. That's what `du` does and what the user is actually paying for.
  #
  # Recorded when backups change rather than computed per page load — walking
  # several thousand files to render a dashboard is the wrong trade. Both
  # numbers are recomputed together on every refresh, so a prune or a delete
  # can't leave the count and the size disagreeing.
  class BackupStats
    STATS_FILE = ".stats.json"

    Stats = Struct.new(:count, :bytes, :computed_at, keyword_init: true) do
      def human_size
        return "0 B" if bytes.to_i <= 0
        units = %w[B KB MB GB TB]
        i = (Math.log(bytes) / Math.log(1024)).floor.clamp(0, units.size - 1)
        value = bytes.to_f / (1024**i)
        "#{value >= 10 || i.zero? ? value.round : value.round(1)} #{units[i]}"
      end
    end

    class << self
      # The recorded numbers, computing them once if nothing has been recorded
      # yet — an install that predates this, or one that hasn't run a backup.
      def current
        read || refresh!
      end

      # Recompute and store. Called after a backup is created, pruned or
      # deleted; both numbers always move together.
      def refresh!
        stats = compute
        write(stats)
        stats
      rescue StandardError => e
        Rails.logger.warn "[SiteSync::BackupStats] refresh failed: #{e.class}: #{e.message}"
        Stats.new(count: 0, bytes: 0, computed_at: nil)
      end

      # Derived from BackupPaths, not from Rails.root — the two disagree under
      # RAILS_ENV=test, where BackupPaths moves to tmp/. Deriving it separately
      # meant the test suite computed from its tmp fixture and wrote the answer
      # into the real backups/.stats.json, so the dashboard reported whatever
      # the last test happened to create.
      def stats_path = File.join(backup_root, STATS_FILE)

      def backup_root = SiteSync::BackupPaths.root

      private

      def compute
        Stats.new(count: backup_count, bytes: disk_bytes, computed_at: Time.current)
      end

      # Timestamped snapshot directories only — not `latest` (a symlink or
      # copy of one that's already counted) and not the live/ subtree.
      def backup_count
        local = SiteSync::BackupPaths.local
        return 0 unless Dir.exist?(local)

        Dir.children(local).count { |name| name.match?(/\A\d{4}-\d{2}-\d{2}/) }
      end

      # Deduplicated by [device, inode] so a hard-linked file is paid for once,
      # and measured in allocated blocks rather than apparent size.
      def disk_bytes
        root = backup_root
        return 0 unless Dir.exist?(root)

        seen = {}
        total = 0

        Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |path|
          next if File.directory?(path) || File.symlink?(path)

          begin
            stat = File.stat(path)
          rescue Errno::ENOENT, Errno::EACCES
            next
          end

          key = [ stat.dev, stat.ino ]
          next if seen[key]

          seen[key] = true
          total += stat.blocks * 512
        end

        total
      end

      def read
        path = stats_path
        return nil unless File.exist?(path)

        data = JSON.parse(File.read(path))
        Stats.new(
          count:       data["count"].to_i,
          bytes:       data["bytes"].to_i,
          computed_at: (Time.parse(data["computed_at"]) if data["computed_at"])
        )
      rescue StandardError
        nil
      end

      def write(stats)
        path = stats_path
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(
          "count" => stats.count, "bytes" => stats.bytes,
          "computed_at" => stats.computed_at&.iso8601
        ))
      rescue StandardError => e
        Rails.logger.warn "[SiteSync::BackupStats] couldn't record stats: #{e.message}"
      end
    end
  end
end
