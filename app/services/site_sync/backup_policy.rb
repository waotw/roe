# frozen_string_literal: true

module SiteSync
  # What goes into a backup, for both kinds: local snapshots
  # (BackupManager) and the copies of live files a sync takes before it
  # overwrites or deletes them (the transports' backup_live_to_local!).
  #
  # Everything is backed up except video web versions (the 720p/1080p
  # renditions and the poster). They are made from the original and can be
  # made again, the same reason image variants were already left out. A
  # video's `-video.json` sits beside them but stays in: it records choices
  # (the poster frame, which sizes were wanted) that can't be rebuilt from
  # the original.
  #
  # Large files are backed up like any other. Over HTTP they come down in
  # pieces (Exchange.download_large_file); over SSH, rsync handles them.
  module BackupPolicy
    module_function

    VIDEO_MANIFEST_SUFFIX = "-video.json"

    # A generated video file: anything in a `variants/` folder under media/
    # except the -video.json settings file. Image variants answer true too,
    # though they're already excluded everywhere by their own rule.
    def video_web_version?(rel)
      parts = rel.to_s.delete_prefix("/").split("/")
      return false unless parts.first == "media" && parts[0..-2].include?("variants")

      !parts.last.end_with?(VIDEO_MANIFEST_SUFFIX)
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
