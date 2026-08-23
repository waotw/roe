# frozen_string_literal: true

require "test_helper"

# memberships_enabled? used to require Stripe keys, which meant a site with
# memberships turned on but billing not yet wired up got no `audience` field
# anywhere — you couldn't mark a post, page, podcast or release paid until
# after you'd connected Stripe. That's backwards: the config says what the site
# is, Stripe says whether it can charge yet.
class MembershipsGatingTest < ActiveSupport::TestCase
  def with_members(payments: true, mode: "memberships")
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteConfig.stubs(:feature).returns(nil)
    SiteConfig.stubs(:feature).with("members", "payments.enabled").returns(payments)
    SiteConfig.stubs(:feature).with("members", "payments.mode").returns(mode)
  end

  def stripe(connected)
    StripeConfig.stubs(:current).returns(stub(keys_present?: connected))
  end

  test "memberships are enabled by config alone" do
    with_members
    stripe(false)

    assert SiteFeature.memberships_enabled?, "config says memberships; Stripe is a separate question"
  end

  test "configured additionally requires Stripe" do
    with_members

    stripe(false)
    assert_not SiteFeature.memberships_configured?

    stripe(true)
    assert SiteFeature.memberships_configured?
  end

  test "neither is true when payments are off" do
    with_members(payments: false)
    stripe(true)

    assert_not SiteFeature.memberships_enabled?
    assert_not SiteFeature.memberships_configured?
  end

  test "a donations-only site has no memberships" do
    with_members(mode: "donations")
    stripe(true)

    assert_not SiteFeature.memberships_enabled?
  end

  test "both mode counts as memberships" do
    with_members(mode: "both")
    stripe(false)

    assert SiteFeature.memberships_enabled?
  end

  # The point of the change: the audience field appears once memberships are
  # configured in the file, not once billing works.
  test "the audience field is offered before Stripe is connected" do
    with_members
    stripe(false)

    assert ContentMetadataSchema.fields_for("post")["audience"][:required]
    assert ContentMetadataSchema.fields_for("page")["audience"][:required]
    assert_includes MusicConfigSchema.release_fields.map { |f| f[:key] }, "audience"
  end
end
