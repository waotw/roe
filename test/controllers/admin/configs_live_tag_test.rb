require "test_helper"

# The configs index shows a "live mode not set up" tag (production only) when a
# deployed integration's active mode works but live keys aren't set. Anchored on
# data-live-unconfigured, not copy.
class Admin::ConfigsLiveTagTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    StripeConfig.delete_all
    PostmarkConfig.delete_all
  end

  test "the live-mode tag appears in production when live keys are missing" do
    SiteFeature.stubs(:payments_feature_enabled?).returns(true)
    SiteFeature.stubs(:payments_live_unconfigured?).returns(true)
    SiteFeature.stubs(:payments_unconfigured?).returns(false)

    get admin_configs_path
    assert_response :success
    assert_select "[data-live-unconfigured]"
  end

  test "no live-mode tag when live keys are set" do
    SiteFeature.stubs(:payments_feature_enabled?).returns(true)
    SiteFeature.stubs(:payments_live_unconfigured?).returns(false)
    SiteFeature.stubs(:payments_unconfigured?).returns(false)

    get admin_configs_path
    assert_response :success
    assert_select "[data-live-unconfigured]", count: 0
  end

  test "the account-not-approved tag appears when Postmark flagged a 412" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    PostmarkConfig.any_instance.stubs(:account_pending_approval?).returns(true)

    get admin_configs_path
    assert_response :success
    assert_select "[data-pending-approval]"
  end
end
