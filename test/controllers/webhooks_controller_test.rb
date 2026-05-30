require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @stripe_config = StripeConfig.current
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      webhook_signing_secret_test: "whsec_test_123"
    )
    @member = create(:member, tier: :free, status: :active)
  end

  # POST /webhooks/stripe
  test "returns 200 for valid checkout.session.completed webhook" do
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
            member_id: @member.id
          }
        }
      }
    }

    # Mock webhook verification
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
    @member.reload
    assert @member.paid?
    assert_equal "cus_test_123", @member.stripe_customer_id
    assert_equal "pi_test_123", @member.stripe_payment_intent_id
  end

  test "returns 400 for invalid signature" do
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

  test "returns 400 for malformed JSON" do
    post "/webhooks/stripe",
      params: "not valid json",
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "some_signature"
      }

    assert_response :bad_request
  end

  test "accepts unverified webhooks when no signing secret configured" do
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
          metadata: { member_id: @member.id }
        }
      }
    }

    # Should construct event without verification and process it
    # Use a pre-built event to avoid double construct_from calls
    mock_event = Stripe::Event.construct_from(event_data.deep_stringify_keys)
    Stripe::Event.expects(:construct_from).once.returns(mock_event)

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :ok
    # Verify member was upgraded
    @member.reload
    assert @member.paid?
  end

  test "ignores webhook when member_id missing from metadata" do
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          metadata: {}
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
    # Member should not be upgraded
    assert_not @member.reload.paid?
  end

  test "ignores webhook when member not found" do
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          metadata: { member_id: 99999 }
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
  end

  test "skips already paid member (idempotent)" do
    # Create a paid member with existing Stripe info
    paid_member = create(:member,
      tier: :paid,
      status: :active,
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
          metadata: { member_id: paid_member.id }
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
    # Should not change - keeps original Stripe info
    paid_member.reload
    assert_equal "cus_existing", paid_member.stripe_customer_id
    assert_equal "pi_existing", paid_member.stripe_payment_intent_id
  end

  test "stores password in cache for success page" do
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_test_123",
          payment_intent: "pi_test_123",
          amount_total: 4900,
          currency: "usd",
          metadata: { member_id: @member.id }
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

    # Password should be stored in cache
    password = Rails.cache.read("member_#{@member.id}_password")
    assert password.present?, "Password should be stored in cache"
    assert @member.reload.authenticate(password)
  end

  test "records payment amount and currency" do
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_test_123",
          payment_intent: "pi_test_123",
          amount_total: 9900,
          currency: "eur",
          metadata: { member_id: @member.id }
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

    @member.reload
    assert_equal 9900, @member.paid_amount_cents
    assert_equal "eur", @member.paid_currency
  end

  test "handles unknown event types gracefully" do
    event_data = {
      type: "unknown.event",
      data: { object: {} }
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
  end

  # CSRF protection
  test "skips CSRF verification" do
    # Should not raise InvalidAuthenticityToken
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          metadata: { member_id: @member.id }
        }
      }
    }

    Stripe::Webhook.expects(:construct_event)
      .returns(Stripe::Event.construct_from(event_data))

    # No CSRF token provided
    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "valid_signature"
      }

    assert_response :ok
  end

  # Error handling
  test "returns 200 even when member upgrade fails" do
    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          customer: "cus_test_123",
          payment_intent: "pi_test_123",
          amount_total: 4900,
          currency: "usd",
          metadata: { member_id: @member.id }
        }
      }
    }

    Stripe::Webhook.expects(:construct_event)
      .returns(Stripe::Event.construct_from(event_data))

    # Force an error during upgrade by making the method raise
    # The error is caught in the controller and logged
    Member.any_instance.stubs(:upgrade_to_paid_with_stripe!)
      .raises(StandardError.new("Database error"))

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "valid_signature"
      }

    # Should return 200 so Stripe doesn't retry
    assert_response :ok
  end

  test "uses correct webhook signing secret based on mode" do
    @stripe_config.update!(mode: :live)
    @stripe_config.update!(
      webhook_signing_secret_live: "whsec_live_456"
    )

    event_data = {
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_123",
          metadata: { member_id: @member.id }
        }
      }
    }

    # Should use live mode secret
    Stripe::Webhook.expects(:construct_event)
      .with(anything, anything, "whsec_live_456")
      .returns(Stripe::Event.construct_from(event_data))

    post "/webhooks/stripe",
      params: event_data.to_json,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "HTTP_STRIPE_SIGNATURE" => "valid_signature"
      }

    assert_response :ok
  end
end
