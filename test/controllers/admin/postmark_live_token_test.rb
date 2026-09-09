require "test_helper"

# Postmark's live token wouldn't save while test keys saved fine.
#
# apply_live_keys writes `<field>_live`, which fits Stripe's paired
# secret_key_test / secret_key_live columns. Postmark is shaped differently:
# the test token lives in postmark.yml and the live one is the single
# encrypted `server_token` column. So server_token_live= doesn't exist, and
# asking for it raised NoMethodError before anything reached the database.
class PostmarkLiveTokenTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    PostmarkConfig.delete_all
    PostmarkService.stubs(:test_connection).returns({ success: true })
    Rails.env.stubs(:production?).returns(true)  # the action is production-only
  end

  teardown { PostmarkConfig.delete_all }

  test "a live token is saved" do
    patch admin_live_newsletters_config_path, params: { live: { server_token: "live-abc-123" } }

    assert_equal "live-abc-123", PostmarkConfig.current.live_server_token
  end

  # The form renders a stored token as bullets; submitting them unchanged must
  # not overwrite the real token with the mask.
  test "the masked placeholder doesn't overwrite a saved token" do
    PostmarkConfig.current.update!(server_token: "live-abc-123")

    patch admin_live_newsletters_config_path, params: { live: { server_token: "•" * 16 } }

    assert_equal "live-abc-123", PostmarkConfig.current.live_server_token
  end

  test "a blank submission leaves the token alone" do
    PostmarkConfig.current.update!(server_token: "live-abc-123")

    patch admin_live_newsletters_config_path, params: { live: { server_token: "" } }

    assert_equal "live-abc-123", PostmarkConfig.current.live_server_token
  end

  # The admin addresses every live field as `<schema key>_live` — the form
  # input, the masking, and apply_live_keys all build that name. Postmark's
  # column is `server_token`, so the model has to answer to both.
  test "the model answers to the name the admin uses" do
    config = PostmarkConfig.current
    config.update!(server_token: "live-abc-123")

    assert_equal "live-abc-123", config.server_token_live
    assert_equal "live-abc-123", config.live_server_token
  end

  # A saved token has to read back as bullets. Reading back blank looks exactly
  # like a save that didn't happen, which is how this was reported.
  test "a saved token shows as masked, not empty" do
    PostmarkConfig.current.update!(server_token: "live-abc-123")

    get admin_edit_newsletters_config_path(tab: "live")

    assert_response :success
    assert_select "input[name='live[server_token]'][value=?]", "•" * 16
  end

  # Live Mode stayed greyed out no matter what was saved: the view guards on
  # respond_to?(:live_mode_ready?), and PostmarkConfig never defined it.
  test "live mode becomes selectable once a token is saved" do
    config = PostmarkConfig.current
    assert_not config.live_mode_ready?, "precondition — no token yet"

    config.update!(server_token: "live-abc-123")

    assert config.live_mode_ready?
  end

  # The mismatch that caused this should be loud where it happens, not a
  # NoMethodError surfacing inside a redirect.
  test "apply_live_keys refuses a record without a live writer" do
    controller = Admin::ConfigsController.new
    record = PostmarkConfig.current
    record.singleton_class.undef_method(:server_token_live=)

    error = assert_raises(ArgumentError) do
      controller.send(:apply_live_keys, record, { "server_token" => "x" }, %w[server_token])
    end

    assert_match "server_token_live=", error.message
  end
end
