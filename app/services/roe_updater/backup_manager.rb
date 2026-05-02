module RoeUpdater
  class BackupManager
    class BackupError < StandardError; end

    class << self
      def backup_databases(status_record)
        backup_dir = File.join(RoeSitePaths::ROE_ROOT, 'site_backups', 'update_tmp')
        FileUtils.mkdir_p(backup_dir)

        # Pick up production DBs from any conventional layout — flat
        # site/db/*.sqlite3 (older convention) or
        # site/db/{development,production}/*.sqlite3 (current).
        databases = Dir.glob(File.join(RoeSitePaths::SITE_PATH, 'db/**/*.sqlite3'))
                       .reject { |p| p =~ /-(?:shm|wal)$/ }

        databases.each do |db|
          backup_path = File.join(backup_dir, File.basename(db))

          # Use SQLite's online backup API instead of cp. Roe runs SQLite
          # in WAL mode, where recent writes can sit in foo.sqlite3-wal
          # before being checkpointed to the main file — a plain `cp`
          # would silently miss those writes. `.backup` issues a
          # consistent snapshot regardless of journal state.
          output = `sqlite3 '#{db}' ".backup '#{backup_path}'" 2>&1`
          unless $?.success?
            raise BackupError, "SQLite .backup failed for #{File.basename(db)}: #{output}"
          end

          unless File.exist?(backup_path) && File.size(backup_path) > 0
            raise BackupError, "Backup verification failed for #{File.basename(db)}"
          end
        end

        status_record.update!(log: (status_record.log || "") + "✓ Database backup created (#{databases.size} files)\n")
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
          # The .backup files are written flat into update_tmp/, but the
          # originals live nested under db/{development,production}/.
          # Find the matching original by basename so we restore to the
          # right subdir regardless of which environment's DB we're
          # rolling back.
          original = Dir.glob(File.join(RoeSitePaths::SITE_PATH, "db/**/#{db_name}")).first

          unless original
            Rails.logger.warn "[RoeUpdater] No original found for #{db_name}, skipping restore"
            next
          end

          # `sqlite3 dest .restore source` is the inverse of .backup —
          # safely overwrites the destination DB even with WAL traffic.
          output = `sqlite3 '#{original}' ".restore '#{backup}'" 2>&1`
          unless $?.success?
            raise BackupError, "SQLite .restore failed for #{db_name}: #{output}"
          end
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
