require "test_helper"
class StripeLocalHideTest < ActionDispatch::IntegrationTest
  # These assert on stable data-test anchors, not copy — the pointer/setup
  # wording is placeholder and changes freely without touching this test.
  setup do
    sign_in_as(User.take)
    StripeConfig.delete_all
    # The hide only applies in development; simulate that here (the suite runs
    # in the test env, where the full UI stays visible).
    Rails.env.stubs(:development?).returns(true)
  end

  test "payments setup is hidden in development, shows the live-site pointer" do
    get admin_edit_payments_config_path
    assert_response :success
    assert_select "[data-test=local-setup-hidden]"
    assert_select "[data-test=stripe-setup]",  count: 0
    assert_select "[data-test=stripe-status]", count: 0
  end

  test "?preview=production reveals the real Stripe UI locally, not the pointer" do
    get admin_edit_payments_config_path(preview: "production")
    assert_response :success
    assert_select "[data-test=local-setup-hidden]", count: 0
    assert_select "[data-test=stripe-status]"
    # Production preview folds key-entry + webhook into per-mode setup panels.
    assert_select "[data-stripe-mode=test]"
    assert_select "[data-stripe-mode=live]"
    # The old standalone Webhook URL reference box is gone for payments.
    assert_select "h3", text: "Webhook URL", count: 0
  end

  test "not-deployed pointer shows deploy links, not the live-admin button" do
    # site_deployed? reads PerformDeployJob::LAST_DEPLOY_FILE (an absolute path to
    # the real install, which may exist on a dev box). Stub the file primitive so
    # this holds regardless of render-instance/order — the any_instance view stub
    # doesn't reliably attach across all suite orderings.
    File.stubs(:exist?).returns(false)
    File.stubs(:exist?).with(PerformDeployJob::LAST_DEPLOY_FILE).returns(false)
    get admin_edit_payments_config_path
    assert_response :success
    assert_select "[data-test=live-admin-link]", count: 0
    assert_select "[data-test=deploy-settings-link]"
  end

  test "override brings the local setup UI back" do
    SiteConfig.stubs(:development).returns(nil)
    SiteConfig.stubs(:development).with("show_local_integration_setup").returns("true")
    get admin_edit_payments_config_path
    assert_response :success
    assert_select "[data-test=stripe-setup]"
    assert_select "[data-test=local-setup-hidden]", count: 0
  end

  test "snipcart local setup is NOT hidden" do
    get admin_edit_snipcart_integration_config_path
    assert_response :success
    assert_select "[data-test=local-setup-hidden]", count: 0
  end
end
