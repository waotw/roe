module RoeUpdater
  class BackupManager
    class BackupError < StandardError; end

    class << self
      def backup_databases(status_record)
        backup_dir = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'update_tmp')
        FileUtils.mkdir_p(backup_dir)

        databases = Dir.glob(File.join(RoeSitePaths::SITE_PATH, 'db/*.sqlite3'))
        
        databases.each do |db|
          backup_path = File.join(backup_dir, File.basename(db))
          FileUtils.cp(db, backup_path)
          
          unless File.exist?(backup_path) && File.size(backup_path) == File.size(db)
            raise BackupError, "Backup verification failed for #{File.basename(db)}"
          end
        end

        status_record.update!(log: (status_record.log || "") + "✓ Database backup created\n")
        backup_dir
      rescue => e
        raise BackupError, "Database backup failed: #{e.message}"
      end

      def backup_full_site(status_record)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        backup_dir = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'update_before', timestamp)
        
        FileUtils.mkdir_p(File.dirname(backup_dir))
        
        rsync_cmd = "rsync -av --delete '#{RoeSitePaths::SITE_PATH}/' '#{backup_dir}/'"
        success = system(rsync_cmd)
        
        unless success
          FileUtils.rm_rf(backup_dir)
          raise BackupError, "Full site backup failed (rsync exit code: #{$?.exitstatus})"
        end

        status_record.update!(log: (status_record.log || "") + "✓ Full site backup created at #{timestamp}\n")
        backup_dir
      rescue => e
        raise BackupError, "Full site backup failed: #{e.message}"
      end

      def restore_databases
        backup_dir = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'update_tmp')
        
        Dir.glob(File.join(backup_dir, '*.sqlite3')).each do |backup|
          db_name = File.basename(backup)
          db_path = File.join(RoeSitePaths::SITE_PATH, 'db', db_name)
          FileUtils.cp(backup, db_path)
        end
        
        FileUtils.rm_rf(backup_dir)
      rescue => e
        Rails.logger.error "Database restore failed: #{e.message}"
        raise BackupError, "Database restore failed: #{e.message}"
      end

      def cleanup_update_backups
        backup_dir = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'update_tmp')
        FileUtils.rm_rf(backup_dir) if File.exist?(backup_dir)
      end
    end
  end
end
