require "test_helper"

# generate_webhook_token is a before_create, and PostmarkConfig.current is
# first_or_create! — so an install whose row predates that callback has no
# token and nothing ever makes one. The admin then hides the entire Webhook URL
# section (the path is nil, so even the "not available" box is skipped), which
# reads as "this install doesn't do webhooks" rather than "something's missing".
class PostmarkWebhookTokenTest < ActiveSupport::TestCase
  setup { PostmarkConfig.delete_all }
  teardown { PostmarkConfig.delete_all }

  test "a new record gets a token as before" do
    assert PostmarkConfig.current.webhook_token.present?
  end

  test "a record with no token is backfilled" do
    config = PostmarkConfig.current
    config.update_column(:webhook_token, nil)   # as an older install looks
    assert_nil config.reload.webhook_token, "precondition — no token"

    token = config.ensure_webhook_token!

    assert token.present?
    assert_equal token, config.reload.webhook_token, "the repair is persisted"
  end

  test "an existing token is never replaced" do
    config = PostmarkConfig.current
    original = config.webhook_token

    config.ensure_webhook_token!

    assert_equal original, config.reload.webhook_token,
      "rotating a live token would break the endpoint already in Postmark"
  end

  test "backfilling twice is stable" do
    config = PostmarkConfig.current
    config.update_column(:webhook_token, nil)

    first = config.ensure_webhook_token!
    second = config.ensure_webhook_token!

    assert_equal first, second
  end
end
