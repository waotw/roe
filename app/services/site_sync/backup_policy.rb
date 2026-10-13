# frozen_string_literal: true

module SiteSync
  # What goes into a backup, for both kinds: local snapshots
  # (BackupManager) and the copies of live files a sync takes before it
  # overwrites or deletes them (the transports' backup_live_to_local!).
  #
  # Backups exist so a sync never destroys the only copy of something you
  # made. Two kinds of file are left out:
  #
  # - Video web versions (the 720p/1080p renditions and the poster). They
  #   are made from the original and can be made again, the same reason
  #   image variants were already left out. A video's `-video.json` sits
  #   beside them but stays in: it records choices (the poster frame, which
  #   sizes were wanted) that can't be rebuilt from the original.
  #
  # - In live backups only, files over LIVE_BACKUP_MAX_BYTES. Downloading a
  #   1.2 GB video from live in one request fails, and that failure stopped
  #   the whole sync. Size comes from live's own file list, which is
  #   reliable; modified times are not. The sync's deletion confirmation
  #   names these files so they can be downloaded first.
  module BackupPolicy
    module_function

    # Same limit Site Sync uses to split uploads into pieces
    # (HttpTransport::PUSH_BATCH_MAX_BYTES): above it, one request is
    # already known to be too big.
    LIVE_BACKUP_MAX_BYTES = 25 * 1024 * 1024

    VIDEO_MANIFEST_SUFFIX = "-video.json"

    # A generated video file: anything in a `variants/` folder under media/
    # except the -video.json settings file. Image variants answer true too,
    # though they're already excluded everywhere by their own rule.
    def video_web_version?(rel)
      parts = rel.to_s.delete_prefix("/").split("/")
      return false unless parts.first == "media" && parts[0..-2].include?("variants")

      !parts.last.end_with?(VIDEO_MANIFEST_SUFFIX)
    end

    def too_large_for_live_backup?(size)
      size.to_i > LIVE_BACKUP_MAX_BYTES
    end

    # Splits the files a sync wants backed up from live into those to copy
    # and those left out for size. Web versions are dropped from both:
    # they're never backed up and nobody needs telling.
    #
    # peer_files is live's manifest: { rel => { "size" => …, "mtime" => … } }.
    def partition_live_backup(paths, peer_files)
      wanted = Array(paths).reject { |rel| video_web_version?(rel) }
      wanted.partition { |rel| !too_large_for_live_backup?(peer_files.dig(rel, "size")) }
    end

    # rsync filter rules for a snapshot of /site, in order: keep each
    # -video.json, then skip the rest of every variants folder. Rules are
    # anchored at /site with a leading "/".
    def rsync_filter_args
      [
        "--include=#{Shellwords.escape("/media/**/variants/*#{VIDEO_MANIFEST_SUFFIX}")}",
        "--exclude=#{Shellwords.escape("/media/**/variants/*")}"
      ]
    end
  end
end
