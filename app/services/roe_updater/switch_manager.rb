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

      def rollback
        return false unless File.exist?(BACKUP_PATH)

        if File.exist?(CURRENT_PATH)
          FileUtils.rm_rf(CURRENT_PATH)
        end

        File.rename(BACKUP_PATH, CURRENT_PATH)

        true
      rescue => e
        Rails.logger.error "Rollback failed: #{e.message}"
        false
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
