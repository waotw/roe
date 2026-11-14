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
          before_mtime = before_sha && File.mtime(abs).to_i
          action = deleted.include?(rel) ? "deleted" : (before_sha ? "changed" : "added")
          note(rel, "to_local", action, before_sha, before_size, before_mtime)
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
              Versions.link_file(copy)
            elsif peer.key?(rel) && !BackupPolicy.video_web_version?(rel)
              raise SaveFailed, "The live version of #{rel} didn't download, so it couldn't be saved. Nothing was sent to live."
            else
              [ nil, peer.dig(rel, "size") ]
            end
          action = deleted.include?(rel) ? "deleted" : (peer.key?(rel) ? "changed" : "added")
          note(rel, "to_live", action, before_sha, before_size, peer.dig(rel, "mtime")&.to_i)
        end
        discard_live_backup(from)
      end

      # The version a path was left at when that isn't the local file — a
      # rewind puts live back to a version local doesn't hold.
      def left_at(rel, sha:, size:, mtime:)
        @changes[rel]&.merge!(after: { after_sha: sha, after_size: size, after_mtime: mtime })
      end

      # Write the run as one event, with each path's new version taken from
      # local disk — after a sync both sides hold it. Never raises: the
      # transfer has happened, and failing to record it mustn't fail it.
      def finish!(kind:, outcome:, at: Time.current, undoes: nil)
        return nil if @changes.empty?

        changes = @changes.values.map do |c|
          next c.except(:after).merge(c[:after]) if c[:after]

          abs = local_path(c[:path])
          present = c[:action] != "deleted" && File.file?(abs)
          after_sha, after_size = present ? Versions.keep_after(abs) : [ nil, nil ]
          c.merge(after_sha: after_sha, after_size: after_size, after_mtime: present ? File.mtime(abs).to_i : nil)
        end
        event_id = Versions.record!(kind: kind, outcome: outcome, at: at, changes: changes, undoes: undoes)
        Versions.trim!
        event_id
      rescue StandardError => e
        Rails.logger.error "[SiteSync::Versions] couldn't record #{kind}: #{e.class} #{e.message}"
        nil
      end

      private

      def note(rel, direction, action, before_sha, before_size, before_mtime)
        @changes[rel] = { path: rel, direction: direction, action: action,
                          before_sha: before_sha, before_size: before_size, before_mtime: before_mtime }
      end

      def local_path(rel) = File.join(RoeSitePaths::SITE_PATH, rel)

      # Once live's copies are in the store, the pre-push backup folder they
      # came in is a second name for the same files: remove it, so the old
      # versions live in one place and backups/live/content/ doesn't grow
      # with every push. Only a folder under that root, and `latest` moves to
      # the newest one left (`rake site:backup` and the rsync transports
      # link against it). Best effort: a folder left behind costs nothing,
      # since its files are hard-linked with the store's.
      def discard_live_backup(dir)
        root = File.expand_path(SiteSync::BackupPaths.live_content)
        dir = dir && File.expand_path(dir)
        return unless dir && File.dirname(dir) == root && File.basename(dir).match?(/\A20\d{2}-/) && File.directory?(dir)

        FileUtils.rm_rf(dir)
        latest = File.join(root, "latest")
        return unless File.symlink?(latest) && !File.exist?(latest)

        FileUtils.rm_f(latest)
        newest = Dir.glob(File.join(root, "20*")).select { |d| File.directory?(d) && !File.symlink?(d) }.max
        FileUtils.ln_s(File.basename(newest), latest) if newest
      rescue StandardError => e
        Rails.logger.warn "[SiteSync::Versions] couldn't remove #{dir}: #{e.class} #{e.message}"
      end
    end
  end
end
