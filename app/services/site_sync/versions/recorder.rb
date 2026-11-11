# frozen_string_literal: true

module SiteSync
  module Versions
    # Collects what one sync replaces and deletes, saving each old version
    # before the transfer touches it, then writes the whole run as one event.
    #
    #   recorder = Versions::Recorder.new
    #   recorder.save_local!(paths)                   # before a pull writes over them
    #   recorder.save_live!(paths, from: dir, peer:)  # live's copies, before a push
    #   ...transfer...
    #   recorder.finish!(kind: :sync, outcome: :completed)
    #
    # save_* raise SaveFailed when an old version can't be kept, which stops
    # the sync before it changes anything: no saved copy, no deletion.
    class Recorder
      def initialize
        @changes = {}
      end

      def any? = @changes.any?

      # Local's copies of `paths`, before a pull replaces or deletes them.
      # `deleted` are the paths the pull will remove.
      def save_local!(paths, deleted: [])
        deleted = Array(deleted).to_set
        Array(paths).uniq.each do |rel|
          abs = local_path(rel)
          before_sha, before_size = File.file?(abs) ? Versions.save_file(abs) : [ nil, nil ]
          action = deleted.include?(rel) ? "deleted" : (before_sha ? "changed" : "added")
          note(rel, "to_local", action, before_sha, before_size)
        end
      end

      # Live's copies of `paths`, from the pre-push backup in `from`, before a
      # push replaces or deletes them. `peer` is live's file list, which says
      # whether each path existed there. A path live has that the backup
      # lacks would be lost by the push — unless it's a video web version,
      # which Roe can make again and backups leave out on purpose.
      def save_live!(paths, from:, peer:, deleted: [])
        deleted = Array(deleted).to_set
        peer ||= {}
        Array(paths).uniq.each do |rel|
          copy = from && File.join(from, rel)
          before_sha, before_size =
            if copy && File.file?(copy)
              Versions.save_file(copy)
            elsif peer.key?(rel) && !BackupPolicy.video_web_version?(rel)
              raise SaveFailed, "live's copy of #{rel} wasn't backed up, so it can't be kept before the push"
            else
              [ nil, peer.dig(rel, "size") ]
            end
          action = deleted.include?(rel) ? "deleted" : (peer.key?(rel) ? "changed" : "added")
          note(rel, "to_live", action, before_sha, before_size)
        end
      end

      # Write the run as one event, with each path's new version taken from
      # local disk — after a sync both sides hold it. Never raises: the
      # transfer has happened, and failing to record it mustn't fail it.
      def finish!(kind:, outcome:, at: Time.current)
        return nil if @changes.empty?

        changes = @changes.values.map do |c|
          abs = local_path(c[:path])
          after_sha, after_size = c[:action] != "deleted" && File.file?(abs) ? Versions.keep_after(abs) : [ nil, nil ]
          c.merge(after_sha: after_sha, after_size: after_size)
        end
        event_id = Versions.record!(kind: kind, outcome: outcome, at: at, changes: changes)
        Versions.trim!
        event_id
      rescue StandardError => e
        Rails.logger.error "[SiteSync::Versions] couldn't record #{kind}: #{e.class} #{e.message}"
        nil
      end

      private

      def note(rel, direction, action, before_sha, before_size)
        @changes[rel] = { path: rel, direction: direction, action: action, before_sha: before_sha, before_size: before_size }
      end

      def local_path(rel) = File.join(RoeSitePaths::SITE_PATH, rel)
    end
  end
end
