require "test_helper"
require "ostruct"

class CheckoutPaymentFlowTest < ActionDispatch::IntegrationTest
  def setup
    super

    @free_member = create(:member,
      name: "Free Member",
      email: "free@example.com",
      tier: :free,
      status: :active
    )

    @stripe_config = StripeConfig.current
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_test_123",
      webhook_signing_secret_test: "whsec_test_123",
      mode: :test,
      verified_at: Time.current
    )

    # Create required pages
    create(:page,
      metadata: {
        "title" => "Upgrade",
        "status" => "published",
        "url_name" => "upgrade"
      },
      content: "# Upgrade\n\nUpgrade to premium."
    )
  end

  # ============================================================================
  # Checkout Initiation
  # ============================================================================

  test "free member can initiate checkout" do
    sign_in_member(@free_member)

    # Mock Stripe session
    mock_session = OpenStruct.new(
      id: "cs_test_123",
      url: "https://checkout.stripe.com/test"
    )

    Stripe::Checkout::Session.expects(:create).returns(mock_session)

    post "/checkout"

    assert_redirected_to "https://checkout.stripe.com/test"
  end

  test "paid member cannot initiate checkout" do
    paid_member = create(:member,
      name: "Paid Member",
      email: "paid@example.com",
      tier: :paid,
      status: :active
    )

    sign_in_member(paid_member)
    post "/checkout"

    assert_redirected_to "/"
    assert_equal "You already have a paid membership", flash[:alert]
  end

  test "guest cannot initiate checkout" do
    post "/checkout"

    assert_redirected_to "/signin"
    assert_equal "Please sign in first", flash[:alert]
  end

  test "checkout fails when stripe not configured" do
    @stripe_config.update!(price_id: nil)

    sign_in_member(@free_member)
    post "/checkout"

    assert_redirected_to "/"
    assert_equal "Payments not available", flash[:alert]
  end

  # ============================================================================
  # Checkout Success Flow
  # ============================================================================

  test "checkout success page renders" do
    get "/checkout/success", params: { session_id: "cs_test_123" }

    assert_response :success
    assert_includes response.body, "Thank you for your purchase!"
  end

  test "checkout success without session_id still renders" do
    get "/checkout/success"

    assert_response :success
  end

  # ============================================================================
  # Checkout Cancel Flow
  # ============================================================================

  test "checkout cancel page renders" do
    get "/checkout/cancel"

    assert_response :success
  end

  # ============================================================================
  # Webhook Processing (Payment Completion)
  # ============================================================================

  test "webhook upgrades member after successful payment" do
    event_data = {
      id: "evt_test_123",
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_test_123",
          payment_intent: "pi_test_123",
          amount_total: 4900,
          currency: "usd",
          metadata: {
            member_id: @free_member.id
          }
        }
      }
    }

    Stripe::Webhook.expects(:construct_event)
      .returns(Stripe::Event.construct_from(event_data))

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "valid_signature"
      }

    assert_response :ok

    # Verify member was upgraded
    @free_member.reload
    assert @free_member.paid?
    assert_equal "cus_test_123", @free_member.stripe_customer_id
  end

  test "webhook generates password for new paid member" do
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_test_123",
          payment_intent: "pi_test_123",
          amount_total: 4900,
          currency: "usd",
          metadata: {
            member_id: @free_member.id
          }
        }
      }
    }

    Stripe::Webhook.expects(:construct_event)
      .returns(Stripe::Event.construct_from(event_data))

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "valid_signature"
      }

    # Password should be stored in cache for display
    password = Rails.cache.read("member_#{@free_member.id}_password")
    assert password.present?

    # Member should be able to authenticate with it
    @free_member.reload
    assert @free_member.authenticate(password)
  end

  # ============================================================================
  # Payment Failure Handling
  # ============================================================================

  test "webhook handles payment failure gracefully" do
    sign_in_member(@free_member)

    Stripe::Checkout::Session.expects(:create)
      .raises(Stripe::StripeError.new("Card declined"))

    post "/checkout"

    assert_redirected_to "/"
    assert_match /Payment error/, flash[:alert]

    # Member should not be upgraded
    @free_member.reload
    assert @free_member.free?
  end

  # ============================================================================
  # Idempotency
  # ============================================================================

  test "webhook is idempotent - does not re-upgrade already paid member" do
    # First, upgrade the member
    @free_member.update!(
      tier: :paid,
      stripe_customer_id: "cus_existing",
      stripe_payment_intent_id: "pi_existing"
    )

    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_new",
          payment_intent: "pi_new",
          amount_total: 4900,
          currency: "usd",
          metadata: {
            member_id: @free_member.id
          }
        }
      }
    }

    Stripe::Webhook.expects(:construct_event)
      .returns(Stripe::Event.construct_from(event_data))

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "valid_signature"
      }

    assert_response :ok

    # Should keep original Stripe info
    @free_member.reload
    assert_equal "cus_existing", @free_member.stripe_customer_id
  end

  # ============================================================================
  # Security
  # ============================================================================

  test "webhook verifies signature" do
    Stripe::Webhook.expects(:construct_event)
      .raises(Stripe::SignatureVerificationError.new("Invalid signature", "header"))

    post "/webhooks/stripe",
      params: {}.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "invalid_signature"
      }

    assert_response :bad_request
  end

  test "webhook accepts unverified in development mode" do
    @stripe_config.update!(webhook_signing_secret_test: nil)

    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_test_123",
          payment_intent: "pi_test_123",
          amount_total: 4900,
          currency: "usd",
          metadata: {
            member_id: @free_member.id
          }
        }
      }
    }

    # Should process without signature verification
    mock_event = Stripe::Event.construct_from(event_data.deep_stringify_keys)
    Stripe::Event.expects(:construct_from).returns(mock_event)

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :ok
  end
end
