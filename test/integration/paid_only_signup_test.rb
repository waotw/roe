require "test_helper"
require "ostruct"

# Paid-only sign-up (members.yml free_signup: false): no free accounts, and
# an account made by the paid button stays pending, signed out, until Stripe
# confirms the payment.
class PaidOnlySignupTest < ActionDispatch::IntegrationTest
  setup do
    StripeConfig.current.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      price_id_test: "price_123",
      verified_at: Time.current
    )
    @checkout = OpenStruct.new(id: "cs_test_123", url: "https://checkout.stripe.com/test")
    @params = { member: { name: "Ann Reader", email: "ann@example.com" } }
    # A refused sign-up re-renders the sign-up page, so the site needs one.
    create(:page, content: "```form\nfor: signup\n```\n",
                  metadata: { "title" => "Sign up", "url_name" => "sign-up" })
  end

  test "a free sign-up is refused and creates nothing" do
    SiteFeature.stubs(:paid_only_signup?).returns(true)

    assert_no_difference -> { Member.count } do
      post "/signup", params: @params
    end
    assert_response :unprocessable_entity
  end

  test "the paid button makes a pending account that isn't signed in" do
    SiteFeature.stubs(:paid_only_signup?).returns(true)
    Stripe::Checkout::Session.expects(:create).with do |args, _opts|
      args[:success_url].include?("/checkout/payment-processing")
    end.returns(@checkout)

    post "/signup_and_checkout", params: @params

    assert_redirected_to "https://checkout.stripe.com/test"
    member = Member.find_by(email: "ann@example.com")
    assert member.status_pending?, "no member until the payment is confirmed"
    assert member.tier_free?
    assert_nil session[:member_id], "a pending account must not be signed in"
    assert_equal member.id, session[:pending_member_id]
  end

  test "trying again after closing the Stripe page reuses the pending account" do
    SiteFeature.stubs(:paid_only_signup?).returns(true)
    Stripe::Checkout::Session.stubs(:create).returns(@checkout)

    post "/signup_and_checkout", params: @params
    assert_no_difference -> { Member.count } do
      post "/signup_and_checkout", params: { member: { name: "Ann R.", email: "ANN@example.com" } }
    end

    assert_redirected_to "https://checkout.stripe.com/test"
    assert_equal "Ann R.", Member.find_by(email: "ann@example.com").name
  end

  test "an active member's email is still refused, not taken over" do
    SiteFeature.stubs(:paid_only_signup?).returns(true)
    create(:member, email: "ann@example.com", tier: :free, status: :active)
    Stripe::Checkout::Session.expects(:create).never

    assert_no_difference -> { Member.count } do
      post "/signup_and_checkout", params: @params
    end
    assert_response :unprocessable_entity
  end

  test "once the payment is confirmed the account is active, and the processing page signs them in" do
    SiteFeature.stubs(:paid_only_signup?).returns(true)
    Stripe::Checkout::Session.stubs(:create).returns(@checkout)
    post "/signup_and_checkout", params: @params
    member = Member.find_by(email: "ann@example.com")

    get "/checkout/payment-processing"
    assert_response :success
    assert_nil session[:member_id], "still waiting: not signed in yet"

    # What WebhooksController#handle_checkout_completed does on payment.
    member.upgrade_to_paid_with_stripe!(customer_id: "cus_1", payment_intent_id: "pi_1",
                                        password: Member.generate_password)
    assert member.reload.status_active?
    assert member.tier_paid?

    get "/checkout/payment-processing"
    assert_redirected_to checkout_success_path
    assert_equal member.id, session[:member_id]
    assert_nil session[:pending_member_id]
  end

  # The ways back for someone who left Stripe without paying.
  test "Try Again on the cancel page restarts checkout for the pending account" do
    SiteFeature.stubs(:paid_only_signup?).returns(true)
    Stripe::Checkout::Session.stubs(:create).returns(@checkout)
    post "/signup_and_checkout", params: @params
    member = Member.find_by(email: "ann@example.com")

    get checkout_cancel_path
    assert_includes response.body, "Your membership starts once the payment goes through."
    assert_select "form[action='#{create_checkout_path}'][data-turbo=false] button", text: "Try Again"

    Stripe::Checkout::Session.unstub(:create)
    Stripe::Checkout::Session.expects(:create).with do |args, _opts|
      args[:customer_email] == "ann@example.com" && args[:metadata][:member_id] == member.id
    end.returns(@checkout)

    post create_checkout_path

    assert_redirected_to "https://checkout.stripe.com/test"
    assert_nil session[:member_id], "still not signed in until it's paid"
  end

  test "signing in with a pending account sends them to sign up, where they finish" do
    SiteFeature.stubs(:member_passwords_enabled?).returns(false)
    create(:member, email: "ann@example.com", tier: :free, status: :pending)
    MemberMailer.expects(:magic_link).never

    post "/signin", params: { member: { email: "ann@example.com" } }

    assert_redirected_to "/sign-up"
    assert_match "payment hasn't gone through", flash[:alert]
    assert_nil session[:member_id]
  end

  test "a site without a sign-up page sends them back to sign in instead" do
    SiteFeature.stubs(:member_passwords_enabled?).returns(false)
    Page.where("json_extract(metadata, '$.url_name') = ?", "sign-up").delete_all
    create(:member, email: "ann@example.com", tier: :free, status: :pending)

    post "/signin", params: { member: { email: "ann@example.com" } }

    assert_redirected_to "/sign-in"
  end

  test "with free sign-ups on, the paid button signs in a free member straight away, as before" do
    SiteFeature.stubs(:paid_only_signup?).returns(false)
    Stripe::Checkout::Session.expects(:create).with do |args, _opts|
      args[:success_url].include?("/checkout/success")
    end.returns(@checkout)

    post "/signup_and_checkout", params: @params

    member = Member.find_by(email: "ann@example.com")
    assert member.status_active?
    assert_equal member.id, session[:member_id]
  end
end
