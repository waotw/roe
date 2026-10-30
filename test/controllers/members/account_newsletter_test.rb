require "test_helper"

# The newsletter switch on the account page. The email unsubscribe link
# (SubscriptionsController) is covered elsewhere; this is the signed-in
# path that doesn't need an email in hand.
class Members::AccountNewsletterTest < ActionDispatch::IntegrationTest
  def setup
    super
    # The newsletter block on the account page is now gated on the newsletter
    # feature being on and configured; these tests exercise the block, so turn
    # the feature on.
    SiteFeature.stubs(:newsletters_enabled?).returns(true)
    @member = create(:member, tier: :free, status: :active,
      name: "Newsletter Reader", email: "reader@example.com")
  end

  test "redirects guest to signin" do
    patch "/account/newsletter", params: { newsletter: "unsubscribe" }
    assert_redirected_to "/sign-in"
    assert @member.reload.newsletter_status_subscribed?
  end

  test "account page shows subscribed state with an unsubscribe button" do
    sign_in_member(@member)
    get "/account"

    assert_response :success
    assert_includes response.body, "You're subscribed"
    assert_includes response.body, "Unsubscribe"
    assert_not_includes response.body, ">Subscribe<"
  end

  test "member can unsubscribe" do
    sign_in_member(@member)
    patch "/account/newsletter", params: { newsletter: "unsubscribe" }

    assert_redirected_to "/account"
    assert @member.reload.newsletter_status_unsubscribed?
    follow_redirect!
    assert_includes response.body, "unsubscribed from the newsletter"
  end

  test "account page shows unsubscribed state with a subscribe button" do
    @member.unsubscribe_from_newsletter!
    sign_in_member(@member)
    get "/account"

    assert_includes response.body, "You're not subscribed"
    assert_includes response.body, ">Subscribe<"
  end

  test "member can resubscribe" do
    @member.unsubscribe_from_newsletter!
    sign_in_member(@member)
    patch "/account/newsletter", params: { newsletter: "subscribe" }

    assert_redirected_to "/account"
    assert @member.reload.newsletter_status_subscribed?
  end

  test "bounced address shows an explanation and no button" do
    @member.update!(newsletter_status: :bounced)
    sign_in_member(@member)
    get "/account"

    assert_includes response.body, "has bounced"
    assert_not_includes response.body, ">Subscribe<"
    assert_not_includes response.body, ">Unsubscribe<"
  end

  test "bounced address cannot be resubscribed from the account page" do
    @member.update!(newsletter_status: :bounced)
    sign_in_member(@member)
    patch "/account/newsletter", params: { newsletter: "subscribe" }

    assert_redirected_to "/account"
    assert @member.reload.newsletter_status_bounced?
  end

  test "unknown value changes nothing" do
    sign_in_member(@member)
    patch "/account/newsletter", params: { newsletter: "whatever" }

    assert_redirected_to "/account"
    assert @member.reload.newsletter_status_subscribed?
  end
end
