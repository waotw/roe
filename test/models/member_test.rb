require "test_helper"
require "ostruct"

class MemberTest < ActiveSupport::TestCase
  # Validations
  test "should require email" do
    member = Member.new(name: "Test User", tier: :free, status: :active)
    assert_not member.valid?
    assert_includes member.errors[:email], "can't be blank"
  end

  test "should require valid email format" do
    member = Member.new(name: "Test User", email: "invalid-email", tier: :free, status: :active)
    assert_not member.valid?
    assert_includes member.errors[:email], "is invalid"
  end

  test "should require unique email case insensitively" do
    create(:member, email: "test@example.com")
    member = Member.new(name: "Test User 2", email: "TEST@EXAMPLE.COM", tier: :free, status: :active)
    assert_not member.valid?
    assert_includes member.errors[:email], "has already been taken"
  end

  test "should require name" do
    member = Member.new(email: "test@example.com", tier: :free, status: :active)
    assert_not member.valid?
    assert_includes member.errors[:name], "can't be blank"
  end

  test "should require tier" do
    member = Member.new(name: "Test User", email: "test@example.com", status: :active)
    member.tier = nil
    assert_not member.valid?
    assert_includes member.errors[:tier], "can't be blank"
  end

  test "should require status" do
    member = Member.new(name: "Test User", email: "test@example.com", tier: :free)
    member.status = nil
    assert_not member.valid?
    assert_includes member.errors[:status], "can't be blank"
  end

  # Callbacks
  test "should generate access token on create" do
    member = create(:member)
    assert_not_nil member.access_token
    assert member.access_token.length > 10
  end

  test "should set subscribed_at on create" do
    member = create(:member)
    assert_not_nil member.subscribed_at
    assert member.subscribed_at <= Time.current
  end

  # Enums
  test "should default to free tier" do
    member = Member.new
    assert_equal "free", member.tier
  end

  test "should default to active status" do
    member = Member.new
    assert_equal "active", member.status
  end

  test "should default to subscribed newsletter_status" do
    member = Member.new
    assert_equal "subscribed", member.newsletter_status
  end

  # Scopes
  test "active scope returns only active members" do
    active_member = create(:member, status: :active)
    create(:member, status: :cancelled)
    
    assert_includes Member.active, active_member
    assert_equal 1, Member.active.count
  end

  test "paid_tier scope returns only paid members" do
    paid_member = create(:member, tier: :paid)
    create(:member, tier: :free)
    
    assert_includes Member.paid_tier, paid_member
    assert_equal 1, Member.paid_tier.count
  end

  test "newsletter_active returns subscribed active members" do
    active_subscribed = create(:member, status: :active, newsletter_status: :subscribed)
    create(:member, status: :active, newsletter_status: :unsubscribed)
    create(:member, status: :cancelled, newsletter_status: :subscribed)
    
    assert_includes Member.newsletter_active, active_subscribed
    assert_equal 1, Member.newsletter_active.count
  end

  test "for_newsletter scope filters by audience" do
    paid_member = create(:member, tier: :paid, status: :active)
    free_member = create(:member, tier: :free, status: :active)
    cancelled_paid = create(:member, tier: :paid, status: :cancelled)
    
    # Paid audience should only include active paid members
    paid_audience = Member.for_newsletter("paid")
    assert_includes paid_audience, paid_member
    assert_not_includes paid_audience, free_member
    assert_not_includes paid_audience, cancelled_paid
    
    # Other audiences include all active members
    other_audience = Member.for_newsletter("everyone")
    assert_includes other_audience, paid_member
    assert_includes other_audience, free_member
    assert_not_includes other_audience, cancelled_paid
  end

  test "not_substack_imported scope filters out imported members" do
    regular_member = create(:member, metadata: {})
    imported_member = create(:member, metadata: { "substack_imported" => true })
    
    assert_includes Member.not_substack_imported, regular_member
    assert_not_includes Member.not_substack_imported, imported_member
  end

  # Instance methods
  test "paid? returns true for paid tier" do
    paid_member = create(:member, tier: :paid)
    free_member = create(:member, tier: :free)
    
    assert paid_member.paid?
    assert_not free_member.paid?
  end

  test "free? returns true for free tier" do
    paid_member = create(:member, tier: :paid)
    free_member = create(:member, tier: :free)
    
    assert_not paid_member.free?
    assert free_member.free?
  end

  test "active? returns true for active status" do
    active_member = create(:member, status: :active)
    cancelled_member = create(:member, status: :cancelled)
    
    assert active_member.active?
    assert_not cancelled_member.active?
  end

  test "cancelled? returns true for cancelled status" do
    active_member = create(:member, status: :active)
    cancelled_member = create(:member, status: :cancelled)
    
    assert_not active_member.cancelled?
    assert cancelled_member.cancelled?
  end

  test "can_access? checks content audience" do
    paid_active = create(:member, tier: :paid, status: :active)
    paid_cancelled = create(:member, tier: :paid, status: :cancelled)
    free_member = create(:member, tier: :free)
    
    # Everyone content accessible to all
    everyone_content = OpenStruct.new(audience: "everyone")
    assert paid_active.can_access?(everyone_content)
    assert paid_cancelled.can_access?(everyone_content)
    assert free_member.can_access?(everyone_content)
    
    # Paid content only accessible to active paid members
    paid_content = OpenStruct.new(audience: "paid")
    assert paid_active.can_access?(paid_content)
    assert_not paid_cancelled.can_access?(paid_content)
    assert_not free_member.can_access?(paid_content)
  end

  test "cancel! sets status to cancelled and records timestamp" do
    member = create(:member, status: :active)
    member.cancel!
    
    assert member.cancelled?
    assert_not_nil member.cancelled_at
  end

  test "reactivate! sets status to active and clears cancelled_at" do
    member = create(:member, status: :cancelled, cancelled_at: 1.day.ago)
    member.reactivate!
    
    assert member.active?
    assert_nil member.cancelled_at
  end

  test "upgrade_to_paid! updates tier and sets password" do
    member = create(:member, tier: :free)
    member.upgrade_to_paid!(password: "secure_password123")
    
    assert member.paid?
    assert member.authenticate("secure_password123")
  end

  test "upgrade_to_paid_with_stripe! updates tier, password, and Stripe fields" do
    member = create(:member, tier: :free)
    member.upgrade_to_paid_with_stripe!(
      customer_id: "cus_test123",
      payment_intent_id: "pi_test456",
      password: "secure_password123",
      amount_cents: 1000,
      currency: "usd"
    )
    
    assert member.paid?
    assert member.authenticate("secure_password123")
    assert_equal "cus_test123", member.stripe_customer_id
    assert_equal "pi_test456", member.stripe_payment_intent_id
    assert_equal 1000, member.paid_amount_cents
    assert_equal "usd", member.paid_currency
    assert_not_nil member.paid_at
  end

  test "stripe_customer? returns true when stripe_customer_id present" do
    member_with_stripe = create(:member, stripe_customer_id: "cus_test")
    member_without_stripe = create(:member, stripe_customer_id: nil)
    
    assert member_with_stripe.stripe_customer?
    assert_not member_without_stripe.stripe_customer?
  end

  test "generate_password creates memorable password format" do
    password = Member.generate_password
    
    # Should be 3 words + 2 digits separated by hyphens
    assert_match(/\A[a-z]+-[a-z]+-[a-z]+-\d{2}\z/, password)
    parts = password.split("-")
    assert_equal 4, parts.length
    assert parts[3].to_i.between?(10, 99)
  end

  test "regenerate_token! creates new access token" do
    member = create(:member)
    old_token = member.access_token
    member.regenerate_token!
    
    assert_not_equal old_token, member.reload.access_token
    assert_not_nil member.access_token
  end

  test "generate_unsubscribe_token returns access token" do
    member = create(:member)
    token = member.generate_unsubscribe_token
    
    assert_equal member.access_token, token
    assert_not_nil token
  end

  test "generate_email_confirmation_token! creates token and timestamp" do
    member = create(:member)
    member.generate_email_confirmation_token!
    
    assert_not_nil member.email_confirmation_token
    assert_not_nil member.email_confirmation_sent_at
  end

  test "confirm_email! updates email when token matches and not expired" do
    member = create(:member, email: "old@example.com", pending_email: "new@example.com")
    member.generate_email_confirmation_token!
    token = member.email_confirmation_token
    
    result = member.confirm_email!(token)
    
    assert result
    assert_equal "new@example.com", member.email
    assert_nil member.pending_email
    assert_nil member.email_confirmation_token
    assert_nil member.email_confirmation_sent_at
  end

  test "confirm_email! returns false when token doesn't match" do
    member = create(:member, email: "old@example.com", pending_email: "new@example.com")
    member.generate_email_confirmation_token!
    
    result = member.confirm_email!("wrong_token")
    
    assert_not result
    assert_equal "old@example.com", member.email
  end

  test "confirm_email! returns false when token expired" do
    member = create(:member, email: "old@example.com", pending_email: "new@example.com")
    member.generate_email_confirmation_token!
    member.update!(email_confirmation_sent_at: 25.hours.ago)
    token = member.email_confirmation_token
    
    result = member.confirm_email!(token)
    
    assert_not result
    assert_equal "old@example.com", member.email
  end

  test "email_confirmation_expired? returns true when token sent over 24 hours ago" do
    member = create(:member, email_confirmation_sent_at: 25.hours.ago)
    assert member.email_confirmation_expired?
  end

  test "email_confirmation_expired? returns false when token sent recently" do
    member = create(:member, email_confirmation_sent_at: 1.hour.ago)
    assert_not member.email_confirmation_expired?
  end

  test "newsletter_subscribed? returns true for subscribed status" do
    subscribed = create(:member, newsletter_status: :subscribed)
    unsubscribed = create(:member, newsletter_status: :unsubscribed)
    
    assert subscribed.newsletter_subscribed?
    assert_not unsubscribed.newsletter_subscribed?
  end

  test "unsubscribe_from_newsletter! updates status to unsubscribed" do
    member = create(:member, newsletter_status: :subscribed)
    member.unsubscribe_from_newsletter!
    
    assert member.newsletter_unsubscribed?
  end

  test "resubscribe_to_newsletter! updates status to subscribed" do
    member = create(:member, newsletter_status: :unsubscribed)
    member.resubscribe_to_newsletter!
    
    assert member.newsletter_subscribed?
  end
end
