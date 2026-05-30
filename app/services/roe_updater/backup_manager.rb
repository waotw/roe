module RoeUpdater
  class BackupManager
    class BackupError < StandardError; end

    # How many timestamped backups to keep per environment under
    # site/db/<env>/backup/. Older ones are pruned at the end of a
    # successful update so the volume doesn't grow unboundedly. The
    # rolled-back-to backup is always the most recent and is preserved.
    BACKUP_RETENTION = 5

    class << self
      # Snapshot every SQLite DB under site/db/{development,production}/
      # to site/db/<env>/backup/<timestamp>/<dbname>.sqlite3. Co-located
      # with the originals so:
      #   - dev backups stay local to dev installs (don't sync to prod)
      #   - prod backups stay on prod (don't sync to local)
      #     (the existing PUSH_EXCLUDES / PULL_EXCLUDES in content.rake
      #      already protect these per-env subdirs)
      #   - restore is obvious — backups live next to what they restore.
      # Returns the timestamp directory created so the orchestrator can
      # reference it later for restore.
      def backup_databases(status_record)
        timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
        created_dirs = []

        databases_by_env.each do |env_dir, db_files|
          backup_dir = File.join(env_dir, "backup", timestamp)
          FileUtils.mkdir_p(backup_dir)
          created_dirs << backup_dir

          db_files.each do |db|
            backup_path = File.join(backup_dir, File.basename(db))

            # SQLite's online backup API — safe under WAL mode where
            # uncheckpointed writes can sit in the -wal sidecar that
            # plain `cp` would miss.
            output = `sqlite3 '#{db}' ".backup '#{backup_path}'" 2>&1`
            unless $?.success?
              raise BackupError, "SQLite .backup failed for #{File.basename(db)}: #{output}"
            end

            unless File.exist?(backup_path) && File.size(backup_path) > 0
              raise BackupError, "Backup verification failed for #{File.basename(db)}"
            end
          end
        end

        if created_dirs.empty?
          status_record.update!(log: (status_record.log || "") + "⊘ No databases found to back up\n")
        else
          file_count = created_dirs.sum { |d| Dir.glob(File.join(d, "*.sqlite3")).size }
          status_record.update!(
            log: (status_record.log || "") + "✓ Database backup created (#{file_count} file(s) at #{timestamp})\n"
          )
        end

        # Stash the timestamp for restore_databases to find. Keyed under
        # the status record's id so concurrent updates (shouldn't happen
        # but defensive) don't trample each other.
        Rails.cache.write(backup_timestamp_cache_key(status_record.id), timestamp, expires_in: 1.hour)

        timestamp
      rescue => e
        raise BackupError, "Database backup failed: #{e.message}"
      end

      # Restore every backed-up DB to its origin path. Looks up the
      # backup timestamp from the cache (stamped during backup_databases)
      # so we restore from the snapshot belonging to THIS update, not
      # whatever happens to be most recent on disk.
      def restore_databases(status_record = nil)
        timestamp = status_record && Rails.cache.read(backup_timestamp_cache_key(status_record.id))

        # Fallback: use the most recent backup across all envs if no
        # timestamp is stashed (e.g. cache evicted, or restore is being
        # called manually). Not as precise but better than failing.
        timestamp ||= most_recent_backup_timestamp

        unless timestamp
          Rails.logger.warn "[RoeUpdater] No backup timestamp available — nothing to restore"
          return
        end

        databases_by_env.each do |env_dir, db_files|
          backup_dir = File.join(env_dir, "backup", timestamp)
          next unless Dir.exist?(backup_dir)

          db_files.each do |original|
            backup_path = File.join(backup_dir, File.basename(original))
            next unless File.exist?(backup_path)

            # `sqlite3 dest .restore source` — inverse of .backup, safe
            # under WAL traffic on the destination.
            output = `sqlite3 '#{original}' ".restore '#{backup_path}'" 2>&1`
            unless $?.success?
              raise BackupError, "SQLite .restore failed for #{File.basename(original)}: #{output}"
            end
          end
        end
      rescue => e
        Rails.logger.error "Database restore failed: #{e.message}"
        raise BackupError, "Database restore failed: #{e.message}"
      end

      # Prune backups beyond BACKUP_RETENTION per environment. Called
      # by complete_update on success — failed updates leave their
      # backup in place for inspection and as the rollback source.
      def prune_old_backups
        databases_by_env.each_key do |env_dir|
          backup_root = File.join(env_dir, "backup")
          next unless Dir.exist?(backup_root)

          # Timestamped subdirs are sortable by name (YYYYMMDD_HHMMSS).
          # Newest last; everything before the last N is fair game.
          all = Dir.children(backup_root).sort.map { |t| File.join(backup_root, t) }
          obsolete = all[0...-BACKUP_RETENTION] || []

          obsolete.each do |dir|
            FileUtils.rm_rf(dir)
            Rails.logger.info "[RoeUpdater] Pruned old backup: #{dir}"
          end
        end
      end

      # Backwards-compatible alias for the orchestrator's existing
      # cleanup call. Now does the retention prune instead of deleting
      # everything — we want the most recent backup to stick around so
      # the user can manually roll back days later if needed.
      def cleanup_update_backups
        prune_old_backups
      end

      private

      # Returns { "<absolute env dir>" => ["<db path>", ...] } where env
      # dir is one of site/db/development, site/db/production, etc.
      # Skips backup/ subdirs and the SQLite -wal/-shm sidecars.
      def databases_by_env
        envs = Dir.glob(File.join(RoeSitePaths::SITE_DB_PATH, "*"))
                  .select { |p| File.directory?(p) && File.basename(p) != "backup" }

        envs.each_with_object({}) do |env_dir, acc|
          dbs = Dir.glob(File.join(env_dir, "*.sqlite3"))
                   .reject { |p| p =~ /-(?:shm|wal)\z/ }
          acc[env_dir] = dbs unless dbs.empty?
        end
      end

      def most_recent_backup_timestamp
        all_timestamps = databases_by_env.keys.flat_map do |env_dir|
          backup_root = File.join(env_dir, "backup")
          next [] unless Dir.exist?(backup_root)
          Dir.children(backup_root)
        end
        all_timestamps.sort.last
      end

      def backup_timestamp_cache_key(status_id)
        "roe_update:backup_timestamp:#{status_id}"
      end
    end
  end
end
