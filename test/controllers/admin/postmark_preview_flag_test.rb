require "test_helper"
class PostmarkPreviewFlagTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take); PostmarkConfig.delete_all }

  test "without the flag, dev shows the single test panel (no live tab)" do
    get admin_edit_newsletters_config_path
    assert_response :success
    assert_select "[data-test=postmark-test-test]"
    assert_select "[data-test=postmark-test-live]", count: 0
  end

  test "?preview=production renders the production UI locally (both tabs)" do
    Rails.env.stubs(:development?).returns(true)
    get admin_edit_newsletters_config_path(preview: "production")
    assert_response :success
    assert_select "[data-test=postmark-test-test]"
    assert_select "[data-test=postmark-test-live]"
  end

  test "the preview flag never persists live keys (dev stays dev for writes)" do
    # The controller gates writes on the real Rails.env, not the preview flag.
    patch admin_live_newsletters_config_path, params: { live: { server_token: "sk" } }
    assert_response :redirect
    assert_nil PostmarkConfig.current.live_server_token
  end
end
