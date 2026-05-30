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

module ActiveSupport
  class TestCase
    parallelize(workers: 0)
    fixtures :all
    include FactoryBot::Syntax::Methods

    def setup
      super
      # Clear cache first to remove any cached SiteConfig
      Rails.cache.clear

      Post.delete_all
      Page.delete_all
      Documentation.delete_all
      Medium.delete_all
      SiteConfig.delete_all

      # Ensure static site mode is disabled for tests
      # This forces requests to go through Rails controllers
      SiteConfig.create!(
        file_path: "site/system/global/site.yml",
        config: { "static_generation_enabled" => false }
      )

      # Reload the SiteConfig cache to pick up the new record
      SiteConfig.reload!("site")
    end
  end
end
