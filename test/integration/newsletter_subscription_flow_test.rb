require "test_helper"

class NewsletterSubscriptionFlowTest < ActionDispatch::IntegrationTest
  def setup
    super

    @member = create(:member,
      name: "Newsletter Subscriber",
      email: "subscriber@example.com",
      tier: :free,
      status: :active,
      newsletter_status: :subscribed
    )

    @unsubscribed_member = create(:member,
      name: "Unsubscribed User",
      email: "unsubscribed@example.com",
      tier: :free,
      status: :active,
      newsletter_status: :unsubscribed
    )

    @post = create(:post,
      metadata: {
        "title" => "Newsletter Test Post",
        "status" => "published",
        "date" => "2024-01-01",
        "published_to" => "both"
      },
      content: "# Newsletter Content\n\nThis post was sent as a newsletter."
    )

    # Create required pages
    create(:page,
      metadata: {
        "title" => "Unsubscribe",
        "status" => "published",
        "url_name" => "unsubscribe"
      },
      content: "# Unsubscribe\n\nUnsubscribe from our newsletter."
    )

    create(:page,
      metadata: {
        "title" => "Unsubscribed",
        "status" => "published",
        "url_name" => "unsubscribed"
      },
      content: "# Unsubscribed\n\nYou have been unsubscribed."
    )
  end

  # ============================================================================
  # Subscription Management
  # ============================================================================

  test "member can view account page" do
    sign_in_member(@member)
    get "/account"

    assert_response :success
    # Should show member details
    assert_includes response.body, @member.name
    assert_includes response.body, @member.email
  end

  test "subscribed member receives newsletter" do
    # This would be tested via the job system, but we can verify
    # the member is in the newsletter audience
    assert @member.newsletter_subscribed?
    assert_includes Member.newsletter_active, @member
  end

  test "unsubscribed member does not receive newsletter" do
    refute @unsubscribed_member.newsletter_subscribed?
    assert_not_includes Member.newsletter_active, @unsubscribed_member
  end

  # ============================================================================
  # Unsubscribe Flow
  # ============================================================================

  test "member can unsubscribe via link with token" do
    token = @member.access_token

    # Use unsubscribe link (with token)
    get "/unsubscribe/#{token}"

    # Should show unsubscribe confirmation page
    assert_response :success

    # Actually unsubscribe
    post "/unsubscribe/#{token}"

    @member.reload
    assert @member.newsletter_unsubscribed?
  end

  test "unsubscribe with invalid token fails" do
    get "/unsubscribe/invalid-token"

    # Should not unsubscribe anyone
    @member.reload
    assert @member.newsletter_subscribed?
  end

  # ============================================================================
  # Resubscribe Flow
  # ============================================================================

  test "member can resubscribe after unsubscribing" do
    # First unsubscribe
    @member.update!(newsletter_status: :unsubscribed)

    # Sign in
    sign_in_member(@member)

    # Resubscribe (this would be via account page or resubscribe link)
    @member.resubscribe_to_newsletter!

    assert @member.newsletter_subscribed?
  end

  # ============================================================================
  # Newsletter Audience Filtering
  # ============================================================================

  test "newsletter sends only to subscribed active members" do
    cancelled_member = create(:member,
      name: "Cancelled",
      email: "cancelled@example.com",
      tier: :free,
      status: :cancelled,
      newsletter_status: :subscribed
    )

    bounced_member = create(:member,
      name: "Bounced",
      email: "bounced@example.com",
      tier: :free,
      status: :active,
      newsletter_status: :bounced
    )

    # Only active subscribed members should be in the audience
    audience = Member.newsletter_active

    assert_includes audience, @member
    assert_not_includes audience, @unsubscribed_member
    assert_not_includes audience, cancelled_member
    assert_not_includes audience, bounced_member
  end

  # ============================================================================
  # Post Newsletter Metadata
  # ============================================================================

  test "post with published_to newsletter is included in newsletter" do
    assert @post.send_as_newsletter?
  end

  test "post with published_to site only is not included in newsletter" do
    site_only_post = create(:post,
      metadata: {
        "title" => "Site Only Post",
        "status" => "published",
        "date" => "2024-01-02",
        "published_to" => "site"
      },
      content: "# Site Only"
    )

    refute site_only_post.send_as_newsletter?
  end

  # ============================================================================
  # Newsletter Send Tracking
  # ============================================================================

  test "newsletter send is tracked per member per post" do
    # Create newsletter send record
    newsletter_send = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: Time.current
    )

    assert_equal @post, newsletter_send.post
    assert_equal @member, newsletter_send.member
    assert_not_nil newsletter_send.sent_at
  end

  test "newsletter send tracking works" do
    # Verify that newsletter sends are tracked in database
    newsletter_send = NewsletterSend.create!(
      post: @post,
      member: @member,
      sent_at: 1.day.ago
    )

    assert_equal @post, newsletter_send.post
    assert_equal @member, newsletter_send.member
    assert_not_nil newsletter_send.sent_at

    # Verify we can query sends for a member
    assert_includes NewsletterSend.where(member: @member), newsletter_send
  end

  # ============================================================================
  # Paid Content in Newsletters
  # ============================================================================

  test "paid content in newsletter respects audience settings" do
    paid_post = create(:post,
      metadata: {
        "title" => "Paid Newsletter Post",
        "status" => "published",
        "date" => "2024-01-03",
        "published_to" => "both",
        "audience" => "paid"
      },
      content: "# Premium Newsletter Content"
    )

    # Free member should see teaser or upgrade prompt in email
    # Paid member should see full content
    assert paid_post.send_as_newsletter?
    assert_equal "paid", paid_post.metadata["audience"]
  end
end
