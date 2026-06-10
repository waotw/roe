require "test_helper"
require "ostruct"

class CheckoutControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member = create(:member, tier: :free, status: :active)
    @stripe_config = StripeConfig.current
  end

  # POST /checkout (create)
  test "redirects to Stripe checkout when member is free and Stripe is configured" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )

    # Sign in the member by setting session directly
    sign_in_member(@member)

    mock_session = OpenStruct.new(
      id: "cs_test_123",
      url: "https://checkout.stripe.com/test"
    )

    Stripe::Checkout::Session.expects(:create).returns(mock_session)

    post "/checkout"

    assert_redirected_to "https://checkout.stripe.com/test"
  end

  test "redirects to root with alert when member already paid" do
    paid_member = create(:member, tier: :paid, status: :active)
    sign_in_member(paid_member)

    post "/checkout"

    assert_redirected_to root_path
    assert_equal "You already have a paid membership", flash[:alert]
  end

  test "redirects to root when Stripe not connected" do
    sign_in_member(@member)

    post "/checkout"

    assert_redirected_to root_path
    assert_equal "Payments not available", flash[:alert]
  end

  test "redirects to root when price_id not set" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    post "/checkout"

    assert_redirected_to root_path
    assert_equal "Payments not available", flash[:alert]
  end

  test "redirects to signin when not authenticated" do
    post "/checkout"

    assert_redirected_to "/signin"
    assert_equal "Please sign in first", flash[:alert]
  end

  test "handles Stripe API errors gracefully" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    Stripe::Checkout::Session.expects(:create)
      .raises(Stripe::StripeError.new("Card declined"))

    post "/checkout"

    assert_redirected_to root_path
    assert_match /Payment error/, flash[:alert]
  end

  test "handles Stripe rate limit errors" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    Stripe::Checkout::Session.expects(:create)
      .raises(Stripe::RateLimitError.new("Rate limit exceeded"))

    post "/checkout"

    assert_redirected_to root_path
    assert_match /Payment error/, flash[:alert]
  end

  # GET /checkout/success
  test "success page renders with session_id" do
    get "/checkout/success", params: { session_id: "cs_test_123" }

    assert_response :success
  end

  test "success page renders without session_id" do
    get "/checkout/success"

    assert_response :success
  end

  # GET /checkout/cancel
  test "cancel page renders successfully" do
    get "/checkout/cancel"

    assert_response :success
  end

  # Metadata tests
  test "includes member_id in checkout session metadata" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    mock_session = OpenStruct.new(id: "cs_test_123", url: "https://checkout.stripe.com/test")

    Stripe::Checkout::Session.expects(:create).with(
      has_entry(:metadata, { member_id: @member.id }),
      anything
    ).returns(mock_session)

    post "/checkout"
  end

  test "uses member email in customer_email" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    mock_session = OpenStruct.new(id: "cs_test_123", url: "https://checkout.stripe.com/test")

    Stripe::Checkout::Session.expects(:create).with(
      has_entry(:customer_email, @member.email),
      anything
    ).returns(mock_session)

    post "/checkout"
  end

  # Edge cases
  test "redirects cancelled member to signin" do
    # Cancelled members cannot sign in via normal flow
    # They would need to reactivate first
    cancelled_member = create(:member, tier: :free, status: :cancelled)

    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )

    # Try to sign in with cancelled member token
    get "/signin/#{cancelled_member.access_token}"

    # Should be redirected with error
    assert_redirected_to "/signin"
    assert_equal "Invalid or expired link", flash[:alert]
  end

  test "line_items includes correct price and quantity" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    mock_session = OpenStruct.new(id: "cs_test_123", url: "https://checkout.stripe.com/test")

    Stripe::Checkout::Session.expects(:create).with(
      has_entry(:line_items, [ {
        price: "price_123",
        quantity: 1
      } ]),
      anything
    ).returns(mock_session)

    post "/checkout"
  end

  test "uses payment mode for checkout session" do
    @stripe_config.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id: "price_123",
      verified_at: Time.current
    )
    sign_in_member(@member)

    mock_session = OpenStruct.new(id: "cs_test_123", url: "https://checkout.stripe.com/test")

    Stripe::Checkout::Session.expects(:create).with(
      has_entry(:mode, "payment"),
      anything
    ).returns(mock_session)

    post "/checkout"
  end
end
