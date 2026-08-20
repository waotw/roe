# frozen_string_literal: true

require "test_helper"

# ai_crawlers lives in security.yml, with the other controls on automated
# traffic. The editors list their sections by hand rather than walking the
# schema, so a setting added to a schema renders nowhere until the view knows
# about it too — which is how this one was invisible the first time.
class Admin::SiteConfigAiCrawlersTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  test "the setting appears on the security.yml form" do
    get admin_edit_security_config_path

    assert_response :success
    assert_includes response.body, "AI Crawlers"
    assert_includes response.body, 'data-config-field="ai_crawlers"'
  end

  test "each mode is offered, labelled rather than named" do
    get admin_edit_security_config_path

    AiCrawlers::MODES.each { |mode| assert_includes response.body, "value=\"#{mode}\"" }
    assert_includes response.body, "Block training and AI answers"
  end

  # An install whose site.yml predates the setting has no value for it, but the
  # behaviour isn't "none" — AiCrawlers falls back to the strictest mode. An
  # empty "Select…" would report something that isn't true.
  test "an install with no value shows the mode actually in force" do
    SiteConfig.stubs(:get).returns(nil)
    get admin_edit_security_config_path

    assert_response :success
    assert_match(/value="#{AiCrawlers::DEFAULT_MODE}" selected/, response.body)
  end


  # Two hand-maintained dispatch lists stand between a schema entry and a
  # rendered form — admin/configs/edit.html.erb picks the partial by config
  # type, and the partial picks its sections the same way. Miss either and the
  # page renders empty with no error, which is how this one shipped twice.
  test "the security form renders its fields, not just its heading" do
    get admin_edit_security_config_path

    assert_response :success
    assert_includes response.body, "Rate Limiting"
    assert_includes response.body, "Limits"
    assert_includes response.body, 'data-config-field="limits.magic_link.to"'
    assert_includes response.body, "config-form", "the form itself has to be there"
  end

  test "the setting is no longer on the site.yml form" do
    get admin_edit_site_config_path

    assert_response :success
    assert_not_includes response.body, 'data-config-field="ai_crawlers"'
  end
end
