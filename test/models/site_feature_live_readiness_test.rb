require "test_helper"

# Live-tier readiness ("live mode not set up") — the production-only signal that
# a deployed store/site has its active mode working but can't take REAL money /
# send REAL email yet because live keys aren't set. Distinct from the active-mode
# "unconfigured" check. Locally it must always be silent (live keys can't be
# saved outside production).
class SiteFeatureLiveReadinessTest < ActiveSupport::TestCase
  setup do
    StripeConfig.delete_all
    PostmarkConfig.delete_all
  end

  # ── Payments (Stripe) ────────────────────────────────────────────────────

  test "payments_live_unconfigured? is false locally even with no live keys" do
    SiteFeature.stubs(:payments_feature_enabled?).returns(true)
    Rails.env.stubs(:production?).returns(false)
    assert_not SiteFeature.payments_live_unconfigured?
  end

  test "payments_live_unconfigured? is true in production when live keys are missing" do
    SiteFeature.stubs(:payments_feature_enabled?).returns(true)
    Rails.env.stubs(:production?).returns(true)
    StripeConfig.any_instance.stubs(:live_mode_ready?).returns(false)
    assert SiteFeature.payments_live_unconfigured?
  end

  test "payments_live_unconfigured? is false in production once live keys are set" do
    SiteFeature.stubs(:payments_feature_enabled?).returns(true)
    Rails.env.stubs(:production?).returns(true)
    StripeConfig.any_instance.stubs(:live_mode_ready?).returns(true)
    assert_not SiteFeature.payments_live_unconfigured?
  end

  test "payments_live_unconfigured? is false when payments feature is off" do
    SiteFeature.stubs(:payments_feature_enabled?).returns(false)
    Rails.env.stubs(:production?).returns(true)
    assert_not SiteFeature.payments_live_unconfigured?
  end

  # ── Email (Postmark) ─────────────────────────────────────────────────────

  test "email_live_unconfigured? is true in production when live token is missing" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    Rails.env.stubs(:production?).returns(true)
    PostmarkConfig.any_instance.stubs(:live_mode_ready?).returns(false)
    assert SiteFeature.email_live_unconfigured?
  end

  test "email_live_unconfigured? is false locally" do
    SiteFeature.stubs(:email_feature_enabled?).returns(true)
    Rails.env.stubs(:production?).returns(false)
    assert_not SiteFeature.email_live_unconfigured?
  end

  # ── Rolls up into the nav dot ────────────────────────────────────────────

  test "the live-tier gap lights the nav dot via any_integration_unconfigured?" do
    Rails.env.stubs(:production?).returns(true)
    # Active mode fine, but live not ready → still needs attention.
    SiteFeature.stubs(:payments_unconfigured?).returns(false)
    SiteFeature.stubs(:email_unconfigured?).returns(false)
    SiteFeature.stubs(:snipcart_unconfigured?).returns(false)
    SiteFeature.stubs(:email_live_unconfigured?).returns(false)
    SiteFeature.stubs(:payments_live_unconfigured?).returns(true)
    assert SiteFeature.any_integration_unconfigured?
  end
end
