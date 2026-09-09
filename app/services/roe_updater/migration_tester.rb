module RoeUpdater
  class MigrationTester
    class MigrationError < StandardError; end

    TEST_SITE_PATH = File.join(RoeSitePaths::ROE_ROOT, "staging", "test_site")

    class << self
      def test_migrations(status_record)
        # Only the last thing this step does is migrations. Before that it
        # copies the whole site, bundles the staged tree and boots a second
        # Rails — none of which is free, and none of which is worth doing for
        # an update that ships no migrations. Most don't.
        if (unapplied = unapplied_staged_versions)&.empty?
          status_record.update!(
            current_step: "Testing migrations...",
            log: (status_record.log || "") + "→ No new migrations in this version, nothing to test\n"
          )
          return true
        end

        status_record.update!(
          current_step: "Testing migrations...",
          log: (status_record.log || "") +
            "→ Testing #{unapplied.size} new #{unapplied.size == 1 ? 'migration' : 'migrations'} on copy...\n"
        )

        copy_site_to_test

        staging_app_path = File.join(RoeSitePaths::ROE_ROOT, "staging")

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

      # The migrations this update would actually run: ones shipped in the
      # downloaded version that this database hasn't applied.
      #
      # Compared against the database rather than against the current
      # checkout's files, so an install already sitting a migration behind
      # still gets its dry run.
      #
      # nil when the answer can't be worked out — no staging directory yet, no
      # migrations found where there should be sixty, or a database that won't
      # answer. The caller tests in that case. Doing the work needlessly costs
      # a minute; skipping a migration that turns out to be broken costs the
      # update, and it's the reason this step exists.
      def unapplied_staged_versions
        directory = File.join(RoeSitePaths::ROE_ROOT, "staging", "db", "migrate")
        return nil unless Dir.exist?(directory)

        staged = Dir.children(directory).filter_map { |name| name[/\A(\d+)_.+\.rb\z/, 1] }
        return nil if staged.empty?

        applied = ActiveRecord::Base.connection
                                    .select_values("SELECT version FROM schema_migrations")
                                    .map(&:to_s)

        staged - applied
      rescue StandardError
        nil
      end

      def copy_site_to_test
        cleanup_test_site

        # Exclude generated image variants - they can be rebuilt from originals
        # This saves significant space during the migration test
        rsync_cmd = "rsync -av --delete --exclude='media/images/variants/' '#{RoeSitePaths::SITE_PATH}/' '#{TEST_SITE_PATH}/' 2>&1"
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
