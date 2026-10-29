# frozen_string_literal: true

require "test_helper"

# The warnings on Settings → Deploy use the same message files as the deploy
# page (app/views/admin/deploy_messages/), so each problem reads the same in
# both places.
class Admin::DeploySettingsMessagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    DeployConfigGenerator.stubs(:fly_cli_available?).returns(true)
    DeployConfigGenerator.stubs(:kamal_cli_available?).returns(true)
    Admin::ConfigsController.any_instance.stubs(:fly_target?).returns(true)
  end

  def shown = response.body.scan(/data-deploy-message="([\w-]+)"/).flatten

  test "signed out of Fly: the sign-in steps, ending with reloading the page" do
    DeployPreflight.any_instance.stubs(:fly_auth_state).returns(:signed_out)
    get admin_edit_deploy_config_path

    assert_response :success
    assert_equal [ "fly_signed_out" ], shown
    assert_match "Reload this page.", response.body
    assert_select "#fly-auth-warning", 1
  end

  # Telling someone to sign in when Fly can't be reached sends them to a
  # command that fails the same way.
  test "Fly unreachable: says so, rather than asking them to sign in" do
    DeployPreflight.any_instance.stubs(:fly_auth_state).returns(:unreachable)
    get admin_edit_deploy_config_path

    assert_equal [ "fly_unreachable" ], shown
    assert_select "#fly-auth-warning", 1
  end

  test "signed in: nothing to say" do
    DeployPreflight.any_instance.stubs(:fly_auth_state).returns(:ok)
    get admin_edit_deploy_config_path

    assert_empty shown
  end

  # The target switch shows and hides these by id.
  test "missing tools keep the ids the target switch toggles" do
    DeployConfigGenerator.stubs(:fly_cli_available?).returns(false)
    DeployConfigGenerator.stubs(:kamal_cli_available?).returns(false)
    get admin_edit_deploy_config_path

    assert_equal %w[fly_cli_missing kamal_cli_missing], shown
    assert_select "#fly-cli-warning", 1
    assert_select "#kamal-cli-warning", 1
    assert_match "getElementById('fly-auth-warning')", response.body
  end
end
