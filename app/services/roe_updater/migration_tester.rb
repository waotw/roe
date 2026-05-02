module RoeUpdater
  class MigrationTester
    class MigrationError < StandardError; end

    TEST_SITE_PATH = File.join(RoeSitePaths::ROE_ROOT, 'staging', 'test_site')

    class << self
      def test_migrations(status_record)
        status_record.update!(
          current_step: "Testing migrations...",
          log: (status_record.log || "") + "→ Testing migrations on copy...\n"
        )

        copy_site_to_test

        staging_app_path = File.join(RoeSitePaths::ROE_ROOT, 'staging')

        # ROE_SITE_PATH is honored by RoeSitePaths in current/config/
        # application.rb — the staging Rails subprocess will boot with
        # SITE_PATH (and therefore SITE_DB_PATH, used in database.yml)
        # pointing at the copied test_site, so migrations run against
        # the COPY rather than the real production DB.
        bundle_cmd = "cd '#{staging_app_path}' && bundle install --quiet 2>&1"
        output = nil
        
        Bundler.with_original_env do
          output = `#{bundle_cmd}`
        end
        
        unless $?.success?
          cleanup_test_site
          raise MigrationError, "Bundle install failed: #{output}"
        end

        # Use the parent's Rails.env, not a hardcoded "production". When
        # the orchestrator is running in real production, that's prod —
        # giving a realistic dry-run. When it's running in dev (e.g.,
        # while testing the update flow itself), we use dev — which is
        # the only env that has working credentials in a dev install.
        # Hardcoding production made dev tests fail with "Missing
        # secret_key_base" before migrations ever ran.
        rails_env = Rails.env
        migrate_cmd = "cd '#{staging_app_path}' && RAILS_ENV=#{rails_env} ROE_SITE_PATH='#{TEST_SITE_PATH}' bundle exec rails db:migrate 2>&1"
        output = nil
        
        Bundler.with_original_env do
          output = `#{migrate_cmd}`
        end
        
        unless $?.success?
          cleanup_test_site
          raise MigrationError, "Migration test failed: #{output}"
        end

        cleanup_test_site

        status_record.update!(
          log: (status_record.log || "") + "✓ Migration test passed\n"
        )

        true
      rescue => e
        cleanup_test_site
        raise MigrationError, "Migration testing failed: #{e.message}"
      end

      private

      def copy_site_to_test
        cleanup_test_site
        
        rsync_cmd = "rsync -av --delete '#{RoeSitePaths::SITE_PATH}/' '#{TEST_SITE_PATH}/' 2>&1"
        output = `#{rsync_cmd}`
        
        unless $?.success?
          raise MigrationError, "Failed to copy site for testing: #{output}"
        end
      end

      def cleanup_test_site
        FileUtils.rm_rf(TEST_SITE_PATH) if File.exist?(TEST_SITE_PATH)
      end
    end
  end
end
