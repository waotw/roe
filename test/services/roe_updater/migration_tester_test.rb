# frozen_string_literal: true

require "test_helper"

# The migration dry-run copies the whole site, bundles the downloaded tree and
# boots a second Rails before it runs anything. That's worth it for an update
# carrying migrations and pure waste for one that isn't — and most aren't.
#
# These test the decision, not the dry run itself: the run needs a real clone
# and a subprocess, so what matters here is that it's skipped only when there is
# genuinely nothing to test.
class RoeUpdater::MigrationTesterTest < ActiveSupport::TestCase
  # ROE_ROOT is the real install even under test, so these write to the same
  # staging/ an update uses. If one is genuinely in progress, stay out of it
  # entirely rather than deleting a clone the updater is relying on.
  def staging_root = File.join(RoeSitePaths::ROE_ROOT, "staging")
  def staging_migrations = File.join(staging_root, "db", "migrate")

  setup do
    skip "an update is in progress — staging/ is in use" if Dir.exist?(staging_root)
    @created_staging = false
  end

  def stage(*versions)
    @created_staging = true
    FileUtils.mkdir_p(staging_migrations)
    versions.each do |version|
      File.write(File.join(staging_migrations, "#{version}_a_migration.rb"), "# test\n")
    end
  end

  def unapplied = RoeUpdater::MigrationTester.send(:unapplied_staged_versions)

  def applied_versions
    ActiveRecord::Base.connection.select_values("SELECT version FROM schema_migrations").map(&:to_s)
  end

  teardown { FileUtils.rm_rf(staging_root) if @created_staging }

  test "an update whose migrations are all applied has nothing to test" do
    stage(*applied_versions.first(3))

    assert_empty unapplied
  end

  test "a migration this database hasn't seen is reported" do
    stage(*applied_versions.first(2), "29991231000000")

    assert_equal [ "29991231000000" ], unapplied
  end

  # Compared against the database, not against current/db/migrate — an install
  # sitting a migration behind still needs its dry run, even though the file is
  # already on disk.
  test "a migration on disk but not in the database still counts" do
    live = Dir.children(Rails.root.join("db/migrate")).filter_map { |n| n[/\A(\d+)_/, 1] }
    behind = live - applied_versions
    skip "this database is fully migrated" if behind.empty?

    stage(*live)

    assert_equal behind.sort, unapplied.sort
  end

  # Every "can't tell" answer has to fall the same way. A minute of needless
  # copying is cheap; skipping a dry run for a migration that turns out to be
  # broken is the thing this step exists to prevent.
  test "no staging directory means test, not skip" do
    assert_nil unapplied, "setup guarantees there isn't one"
  end

  test "a staging tree with no migrations at all means test, not skip" do
    @created_staging = true
    FileUtils.mkdir_p(staging_migrations)

    assert_nil unapplied, "sixty migrations ship with every version; none means something is wrong"
  end

  test "files that aren't migrations are ignored" do
    @created_staging = true
    FileUtils.mkdir_p(staging_migrations)
    File.write(File.join(staging_migrations, "README.md"), "not a migration\n")
    File.write(File.join(staging_migrations, "schema.rb"), "not a migration\n")

    assert_nil unapplied
  end
end
