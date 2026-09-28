require "test_helper"

# The Stripe key-save flow now sets up the webhook automatically — no separate
# "Set up webhook" button. Saving the restricted key verifies it, then (when a
# public URL exists) creates/refreshes the endpoint and captures the signing
# secret. StripeWebhookSetup is stubbed; it's unit-tested elsewhere.
class Admin::PaymentsAutoWebhookTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    StripeConfig.delete_all
  end

  def with_webhook_url(host = "https://tunnel.example.com")
    Admin::ConfigsController.any_instance.stubs(:webhook_url).returns("#{host}/webhooks/stripe")
    yield
  end

  test "saving the test key auto-creates the webhook and stores the signing secret" do
    with_webhook_url do
      StripeConfig.any_instance.stubs(:verify!).returns(true).then.returns(true)
      StripeConfig.any_instance.stubs(:verified_at).returns(Time.current)
      StripeWebhookSetup.any_instance.stubs(:ensure_endpoint)
                        .returns(id: "we_1", signing_secret: "whsec_auto", recreated: false)

      patch admin_payments_config_path, params: { test: { secret_key: "sk_test_x" } }

      assert_redirected_to admin_edit_payments_config_path(tab: "test")
      assert_equal "whsec_auto", StripeConfig.current.webhook_signing_secret_test
      assert_match(/webhook connected/i, flash[:notice])
    end
  end

  test "saving locally without a public URL skips webhook setup, keeps the key" do
    # No webhook_url stub → blank URL → auto-setup is a silent no-op.
    Admin::ConfigsController.any_instance.stubs(:webhook_url).returns(nil)
    StripeConfig.any_instance.stubs(:verify!).returns(true)
    StripeConfig.any_instance.stubs(:verified_at).returns(Time.current)
    # If it tried, this would blow up — proving it never runs.
    StripeWebhookSetup.any_instance.stubs(:ensure_endpoint).raises("should not be called")

    patch admin_payments_config_path, params: { test: { secret_key: "sk_test_x" } }

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
    assert_equal "sk_test_x", StripeConfig.current.secret_key_test
    assert_nil StripeConfig.current.webhook_signing_secret_test
  end

  test "a webhook failure on save doesn't lose the saved key" do
    with_webhook_url do
      StripeConfig.any_instance.stubs(:verify!).returns(true)
      StripeConfig.any_instance.stubs(:verified_at).returns(Time.current)
      StripeWebhookSetup.any_instance.stubs(:ensure_endpoint)
                        .raises(StripeWebhookSetup::Error.new("Invalid API Key provided"))

      patch admin_payments_config_path, params: { test: { secret_key: "sk_test_x" } }

      assert_equal "sk_test_x", StripeConfig.current.secret_key_test
      assert_match(/couldn't be set up/i, flash[:notice])
    end
  end
end
