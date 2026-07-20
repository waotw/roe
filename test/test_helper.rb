ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/markdown_fixture"
require "factory_bot"

FactoryBot.find_definitions

# Use memory store for caching in tests
Rails.cache = ActiveSupport::Cache::MemoryStore.new

# ── Test site skeleton ───────────────────────────────────────────────────────
# Under RAILS_ENV=test, RoeSitePaths::SITE_PATH resolves to
# <ROE_ROOT>/tmp/test_site/ (see config/application.rb). Wipe and recreate
# the structure once at suite start so every test run begins from a known
# blank slate. The real /site directory is never touched.
TEST_SITE_PATH = RoeSitePaths::SITE_PATH
FileUtils.rm_rf(TEST_SITE_PATH)
%w[
  system/integrations
  system/features
  system/global
  system/defaults
  system/assets/fonts
  system/assets/images
  posts
  pages
  documentation
  media
  theme
  layout
  emails
].each { |sub| FileUtils.mkdir_p(File.join(TEST_SITE_PATH, sub)) }

# Seed the default email templates that EmailRenderer expects to find.
# Copying directly from the template kit instead of routing through
# ConfigGenerator so the test rig stays decoupled from feature-toggle
# orchestration (members.yml, pages, integrations). Skip-if-exists
# matches the previous generate_member_emails behaviour.
emails_src = Rails.root.join("lib", "site_templates", "features", "members", "emails")
emails_dst = File.join(TEST_SITE_PATH, "emails")
FileUtils.mkdir_p(emails_dst)
emails_src.each_child do |source|
  target = File.join(emails_dst, source.basename.to_s)
  FileUtils.cp(source, target) unless File.exist?(target)
end

# Seed a minimal site.yml so SiteConfig.current("site") resolves through
# the same find_by(file_path:) → create_from_file path it uses in
# production. Disabling static_generation_enabled forces requests
# through Rails controllers (instead of the StaticSiteMiddleware).
File.write(
  SiteConfig::SITE_FILE,
  { "static_generation_enabled" => false }.to_yaml.sub(/\A---\s*\n/, "")
)

module ActiveSupport
  class TestCase
    parallelize(workers: 0)
    fixtures :all
    include FactoryBot::Syntax::Methods

    setup do
      # Clear cache first to remove any cached SiteConfig
      Rails.cache.clear

      Post.delete_all
      Page.delete_all
      Documentation.delete_all
      Medium.delete_all
      SiteConfig.delete_all
      PostmarkConfig.delete_all
      StripeConfig.delete_all
      Member.delete_all

      # Each test starts with no integration config files so writes are
      # observable from a known empty state. Cheap — these are tiny yml.
      Dir.glob(File.join(RoeSitePaths::SITE_PATH, "system/integrations", "*.yml")).each do |f|
        File.delete(f)
      end

      # Rewrite site.yml to the clean default — SiteConfig.get reads
      # directly from the file on disk (not DB/cache), so a test that
      # writes a non-default site.yml (e.g. search_all_pages: true)
      # would pollute every subsequent test in random order.
      File.write(
        SiteConfig::SITE_FILE,
        { "static_generation_enabled" => false }.to_yaml.sub(/\A---\s*\n/, "")
      )

      # content.yml (search + content-rendering settings, split out of
      # site.yml) is likewise read from disk, so a test that writes a
      # non-default content.yml (e.g. search.all_pages: true) would pollute
      # later tests in random order. Remove it so each test starts from the
      # built-in defaults, exactly as the site.yml rewrite above does.
      File.delete(SiteConfig::CONTENT_FILE) if File.exist?(SiteConfig::CONTENT_FILE)

      # Sync the seeded site.yml into a SiteConfig record. Uses the same
      # path production does (find_by(file_path:) → create_from_file)
      # rather than constructing a record by hand.
      SiteConfig.sync_from_file("site")
      SiteConfig.reload!("site")
    end
  end
end
