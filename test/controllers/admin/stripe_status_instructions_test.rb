require "test_helper"

# When the active-mode key is saved but the webhook isn't working, the setup
# panel must say what's wrong and offer a retry — not just read "not set up".
class Admin::StripeStatusInstructionsTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    StripeConfig.delete_all
    Rails.env.stubs(:development?).returns(true) # reveal the real UI in dev
  end

  def preview(**p) = get admin_edit_payments_config_path(preview: "production", **p)

  test "unverified key shows the rejected-key instructions" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    StripeConfig.any_instance.stubs(:verify!).returns(false)
    StripeConfig.any_instance.stubs(:verified_at).returns(nil)
    preview
    assert_select "[data-test=stripe-key-unverified-test]"
    assert_select "[data-test=stripe-webhook-missing-test]", count: 0
  end

  test "verified key with a URL but no registered webhook shows retry" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x")
    StripeConfig.any_instance.stubs(:verify!).returns(true)
    StripeConfig.any_instance.stubs(:verified_at).returns(Time.current)
    SiteConfig.stubs(:development).returns(nil)
    SiteConfig.stubs(:development).with("dev_host").returns("dev.example.com")
    StripeConfig.any_instance.stubs(:webhook_configured?).returns(false)
    preview
    assert_select "[data-test=stripe-webhook-missing-test]"
    assert_select "form[action=?]", admin_setup_payments_webhook_config_path
  end

  test "fully connected shows the green check, no instructions" do
    StripeConfig.save_test_config("secret_key" => "sk_test_x", "webhook_signing_secret" => "whsec_x")
    StripeConfig.any_instance.stubs(:verify!).returns(true)
    StripeConfig.any_instance.stubs(:verified_at).returns(Time.current)
    SiteConfig.stubs(:development).returns(nil)
    SiteConfig.stubs(:development).with("dev_host").returns("dev.example.com")
    StripeConfig.any_instance.stubs(:webhook_configured?).returns(true)
    preview
    assert_select "[data-test=stripe-webhook-ok-test]"
    assert_select "[data-test=stripe-webhook-missing-test]", count: 0
    assert_select "[data-test=stripe-key-unverified-test]", count: 0
  end
end
