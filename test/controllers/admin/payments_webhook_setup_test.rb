require "test_helper"

# Covers the Stripe webhook auto-setup action: it captures the signing secret
# StripeWebhookSetup returns and stores it, and refuses the paths that can't
# work (no key, live-in-dev). The service itself is unit-tested separately in
# test/services/stripe_webhook_setup_test.rb — here we stub it.
class Admin::PaymentsWebhookSetupTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    StripeConfig.delete_all
    # A test secret key present so the action gets past the key guard, and a
    # dev_host so webhook_url resolves in the test environment.
    StripeConfig.save_test_config("secret_key" => "sk_test_x", "publishable_key" => "pk_test_x")
    SiteConfig.stubs(:get).returns(nil)
  end

  def with_webhook_url(host = "https://tunnel.example.com")
    # WebhookUrlHelper#webhook_url is mixed into Admin::ConfigsController; stub
    # it there so the action gets a resolvable URL in the test environment.
    Admin::ConfigsController.any_instance.stubs(:webhook_url).returns("#{host}/webhooks/stripe")
    yield
  end

  test "creates the webhook and stores the captured signing secret" do
    with_webhook_url do
      StripeWebhookSetup.any_instance.stubs(:ensure_endpoint)
                        .returns(id: "we_1", signing_secret: "whsec_captured", recreated: false)
      StripeConfig.any_instance.stubs(:verify!).returns(true)

      post admin_setup_payments_webhook_config_path

      assert_redirected_to admin_edit_payments_config_path(tab: "test")
      assert_equal "whsec_captured", StripeConfig.current.webhook_signing_secret_test
      assert_match(/created/i, flash[:notice])
    end
  end

  test "reports a refresh when an existing endpoint was recreated" do
    with_webhook_url do
      StripeWebhookSetup.any_instance.stubs(:ensure_endpoint)
                        .returns(id: "we_1", signing_secret: "whsec_new", recreated: true)
      StripeConfig.any_instance.stubs(:verify!).returns(true)

      post admin_setup_payments_webhook_config_path
      assert_match(/refreshed/i, flash[:notice])
    end
  end

  test "surfaces a friendly error when Stripe rejects the request" do
    with_webhook_url do
      StripeWebhookSetup.any_instance.stubs(:ensure_endpoint)
                        .raises(StripeWebhookSetup::Error.new("Invalid API Key provided"))

      post admin_setup_payments_webhook_config_path
      assert_match(/Invalid API Key/i, flash[:alert])
      assert_nil StripeConfig.current.webhook_signing_secret_test
    end
  end

  test "refuses when no secret key is configured for the mode" do
    StripeConfig.clear_test_config
    StripeConfig.current # reset with no keys
    with_webhook_url do
      post admin_setup_payments_webhook_config_path
      assert_match(/secret key first/i, flash[:alert])
    end
  end

  test "refuses live webhook setup outside production" do
    # mode stays test in dev (StripeConfig.current forces it), so assert the
    # guard by forcing live and confirming it's rejected before any API call.
    StripeConfig.current.update_column(:mode, 1)
    Rails.env.stubs(:production?).returns(false)
    with_webhook_url do
      post admin_setup_payments_webhook_config_path
      assert_match(/only set up in production/i, flash[:alert])
    end
  end
end
