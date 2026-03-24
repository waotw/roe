ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "factory_bot"

FactoryBot.find_definitions

module ActiveSupport
  class TestCase
    parallelize(workers: 0)
    fixtures :all
    include FactoryBot::Syntax::Methods

    def setup
      super
      Post.delete_all
      Page.delete_all
      Documentation.delete_all
      Medium.delete_all
      SiteConfig.delete_all
    end
  end
end
