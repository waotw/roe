module RoeUpdater
  class UpdateOrchestrator
    STEPS = [
      { name: 'validating', percent: 5, description: 'Validating update prerequisites' },
      { name: 'backing_up_db', percent: 15, description: 'Creating database backup' },
      { name: 'backing_up_site', percent: 25, description: 'Creating full site backup' },
      { name: 'downloading', percent: 40, description: 'Downloading new version' },
      { name: 'testing', percent: 55, description: 'Testing migrations' },
      { name: 'migrating', percent: 70, description: 'Running production migrations' },
      { name: 'switching', percent: 85, description: 'Switching to new version' },
      { name: 'restarting', percent: 95, description: 'Restarting server' },
      { name: 'completed', percent: 100, description: 'Update complete' }
    ].freeze

    class << self
      def start_update(to_version, status_record)
        @status = status_record
        @version = to_version

        execute_step(:validating) { validate_prerequisites }
        execute_step(:backing_up_db) { BackupManager.backup_databases(@status) }
        execute_step(:backing_up_site) { BackupManager.backup_full_site(@status) }
        execute_step(:downloading) { Downloader.download_version(@version, @status) }
        execute_step(:testing) { MigrationTester.test_migrations(@status) }
        execute_step(:migrating) { run_production_migrations }
        execute_step(:switching) { SwitchManager.switch_versions(@status) }
        execute_step(:restarting) { restart_server }

        complete_update
      rescue => e
        handle_failure(e)
      end

      private

      def execute_step(step_name)
        step = STEPS.find { |s| s[:name] == step_name.to_s }
        
        @status.update!(
          current_step: step[:description],
          progress_percent: step[:percent]
        )

        log("Starting: #{step[:description]}")
        
        begin
          yield
          log("Completed: #{step[:description]}")
        rescue => e
          log("Failed at #{step[:description]}: #{e.message}")
          raise
        end
      end

      def validate_prerequisites
        unless git_available?
          raise "Git is not available. Please install Git to perform updates."
        end

        if File.exist?(File.join(RoeSitePaths::ROE_ROOT, 'staging'))
          raise "Staging directory already exists. Please clean up manually or wait for current update to complete."
        end
      end

      def run_production_migrations
        log("Running production migrations...")
        
        current_app = File.join(RoeSitePaths::ROE_ROOT, 'current')
        
        env_vars = {
          'RAILS_ENV' => 'production'
        }
        
        migrate_cmd = "cd '#{current_app}' && RAILS_ENV=production bundle exec rails db:migrate 2>&1"
        output = nil
        
        Bundler.with_original_env do
          output = `#{migrate_cmd}`
        end
        
        unless $?.success?
          raise "Production migration failed: #{output}"
        end
        
        log("Production migrations completed")
      end

      def restart_server
        log("Initiating server restart...")
        
        Thread.new do
          sleep 2
          exit!(0)
        end
        
        log("Server restart scheduled")
      end

      def complete_update
        @status.update!(
          status: 'completed',
          current_step: 'Update completed successfully',
          completed_at: Time.current
        )

        BackupManager.cleanup_update_backups
        SwitchManager.cleanup_backup
        
        log("✓ Update completed successfully!")
      end

      def handle_failure(error)
        log("Update failed: #{error.message}")
        log("Initiating automatic rollback...")
        
        begin
          BackupManager.restore_databases
          SwitchManager.rollback
          BackupManager.cleanup_update_backups
          
          @status.update!(
            status: 'rolled_back',
            error_message: error.message,
            current_step: "Rolled back to previous version"
          )
          
          log("Rollback completed")
        rescue => rollback_error
          log("CRITICAL: Rollback failed: #{rollback_error.message}")
          @status.update!(
            status: 'failed',
            error_message: "#{error.message}. Rollback also failed: #{rollback_error.message}",
            current_step: "CRITICAL: Manual intervention required"
          )
        end
      end

      def log(message)
        timestamp = Time.current.strftime("%H:%M:%S")
        current_log = @status.log || ""
        @status.update!(log: current_log + "[#{timestamp}] #{message}\n")
        Rails.logger.info "[RoeUpdater] #{message}"
      end

      def git_available?
        system('which git > /dev/null 2>&1')
      end
    end
  end
end
