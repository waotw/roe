module RoeUpdater
  class SwitchManager
    class SwitchError < StandardError; end

    CURRENT_PATH = File.join(RoeSitePaths::ROE_ROOT, "current")
    BACKUP_PATH = File.join(RoeSitePaths::ROE_ROOT, "current.backup")
    STAGING_PATH = File.join(RoeSitePaths::ROE_ROOT, "staging")

    class << self
      def switch_versions(status_record)
        status_record.update!(
          current_step: "Switching to new version...",
          log: (status_record.log || "") + "→ Switching versions...\n"
        )

        unless File.exist?(STAGING_PATH)
          raise SwitchError, "Staging directory not found"
        end

        if File.exist?(BACKUP_PATH)
          FileUtils.rm_rf(BACKUP_PATH)
        end

        if File.exist?(CURRENT_PATH)
          File.rename(CURRENT_PATH, BACKUP_PATH)
        end

        File.rename(STAGING_PATH, CURRENT_PATH)

        status_record.update!(
          log: (status_record.log || "") + "✓ Switched to new version\n"
        )

        true
      rescue => e
        rollback_if_needed
        raise SwitchError, "Version switch failed: #{e.message}"
      end

      # Restore the pre-update directory by renaming current.backup →
      # current. Used by UpdateOrchestrator#handle_failure when a later
      # step blows up partway through.
      #
      # The previous implementation did `rm_rf(current) + rename(backup,
      # current)`, which sounded fine but lost a race against asset
      # builds and bootsnap: by the time rm_rf finished walking the tree,
      # Tailwind's watcher or Rails' bootsnap cache had already written
      # NEW files into the half-deleted current/ (typically
      # app/assets/build/tailwind.css and tmp/cache/bootsnap/*). The
      # follow-up `File.rename(backup, current)` then failed with
      # `Errno::ENOTEMPTY (Directory not empty)` because POSIX rename
      # refuses to overwrite a non-empty directory — and the old rescue
      # silently turned that into `return false`. The orchestrator logged
      # "Rollback completed" while the filesystem was still wrecked.
      #
      # Rename-to-quarantine fixes this: the broken current/ moves out
      # of the way atomically (rename of a directory within the same
      # filesystem is a single inode operation — no walk, no window for
      # asset writers to interfere), the backup slides into its place,
      # and the quarantined copies get cleaned up afterwards. Failures
      # are NOT rescued here — they propagate to handle_failure so the
      # user sees the real reason in the admin UI.
      def rollback
        return false unless File.exist?(BACKUP_PATH)

        if File.exist?(CURRENT_PATH)
          quarantine = "#{CURRENT_PATH}.broken-#{Time.current.to_i}"
          File.rename(CURRENT_PATH, quarantine)
        end

        File.rename(BACKUP_PATH, CURRENT_PATH)

        Dir.glob("#{CURRENT_PATH}.broken-*").each do |dir|
          FileUtils.rm_rf(dir)
        rescue => e
          Rails.logger.warn "Could not clean up quarantine #{dir}: #{e.message}"
        end

        true
      end

      def cleanup_backup
        FileUtils.rm_rf(BACKUP_PATH) if File.exist?(BACKUP_PATH)
      end

      private

      def rollback_if_needed
        if File.exist?(BACKUP_PATH) && !File.exist?(CURRENT_PATH)
          File.rename(BACKUP_PATH, CURRENT_PATH)
        end
      end
    end
  end
end
