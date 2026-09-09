# frozen_string_literal: true

require "test_helper"

# Email used to be gated on newsletter.enabled. A site running free members with
# newsletters off therefore never had postmark.yml generated and never saw the
# setting in Settings — so every sign-in email fell through to a fallback mailer
# that returns success and delivers nothing. Members couldn't sign in, silently.
#
# A magic link IS the sign-in mechanism, so email isn't optional alongside
# members: it's required by them. newsletter.enabled now means what it says —
# whether posts go out as broadcasts.
class EmailFeatureTest < ActiveSupport::TestCase
  def with_members(enabled, newsletter:)
    SiteFeature.stubs(:members_enabled?).returns(enabled)
    # The catch-all first: any_integration_unconfigured? also asks about
    # payments and the store, and an unstubbed call would raise.
    SiteConfig.stubs(:feature).returns(false)
    SiteConfig.stubs(:feature).with("members", "newsletter.enabled").returns(newsletter)
    SiteFeature.stubs(:store_enabled?).returns(false)
  end

  test "email follows members, not newsletters" do
    with_members(true, newsletter: false)

    assert SiteFeature.email_feature_enabled?, "members need email whether or not they get a newsletter"
    assert_not SiteFeature.newsletters_feature_enabled?
  end

  test "members off means no email either" do
    with_members(false, newsletter: true)

    assert_not SiteFeature.email_feature_enabled?
    assert_not SiteFeature.newsletters_feature_enabled?, "newsletters have always required members"
  end

  test "newsletters still require both" do
    with_members(true, newsletter: true)

    assert SiteFeature.email_feature_enabled?
    assert SiteFeature.newsletters_feature_enabled?
  end

  # The orange dot. A members site with no working email is broken whether or
  # not it ever sends a broadcast, so the warning has to appear either way.
  test "unconfigured email is flagged with newsletters off" do
    with_members(true, newsletter: false)
    SiteFeature.stubs(:postmark_configured?).returns(false)

    assert SiteFeature.email_unconfigured?
    assert SiteFeature.any_integration_unconfigured?
  end

  test "configured email is not flagged" do
    with_members(true, newsletter: false)
    SiteFeature.stubs(:postmark_configured?).returns(true)

    assert_not SiteFeature.email_unconfigured?
  end

  test "a site with no members is not nagged about email" do
    with_members(false, newsletter: false)
    SiteFeature.stubs(:postmark_configured?).returns(false)

    assert_not SiteFeature.email_unconfigured?
  end
end
