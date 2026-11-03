require "test_helper"

# members.yml `free_signup`: on unless it says false, so a members.yml from
# before the setting existed keeps free sign-ups.
class SiteFeatureFreeSignupTest < ActiveSupport::TestCase
  setup do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteConfig.stubs(:feature).returns(nil)
  end

  test "free sign-ups are on when members.yml has no free_signup key" do
    assert SiteFeature.free_signup_enabled?
    assert_not SiteFeature.paid_only_signup?
  end

  test "free_signup: false makes sign-up paid only" do
    SiteConfig.stubs(:feature).with("members", "free_signup").returns(false)

    assert_not SiteFeature.free_signup_enabled?
    assert SiteFeature.paid_only_signup?
  end

  test "a quoted \"false\" counts as off too" do
    SiteConfig.stubs(:feature).with("members", "free_signup").returns("false")

    assert SiteFeature.paid_only_signup?
  end

  test "free_signup: true keeps free sign-ups" do
    SiteConfig.stubs(:feature).with("members", "free_signup").returns(true)

    assert SiteFeature.free_signup_enabled?
    assert_not SiteFeature.paid_only_signup?
  end

  test "a site without members is never paid only" do
    SiteFeature.stubs(:members_enabled?).returns(false)
    SiteConfig.stubs(:feature).with("members", "free_signup").returns(false)

    assert_not SiteFeature.paid_only_signup?
  end
end
