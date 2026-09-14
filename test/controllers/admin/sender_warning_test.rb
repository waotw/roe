# frozen_string_literal: true

require "test_helper"

# The warning exists so nobody finds out from a failed sign-in that their site
# has no address to send from.
class Admin::SenderWarningTest < ActionDispatch::IntegrationTest
  # edit_members redirects when features/members.yml is absent, so these tests
  # need one. It's shared test-site state — a sibling test deleting it has
  # caused an order-dependent flake before — so put back exactly what was here.
  MEMBERS_YML = SiteConfig::FEATURES_PATH.join("members.yml")

  setup do
    sign_in_as(User.take)
    @members_yml_existed = File.exist?(MEMBERS_YML)
    unless @members_yml_existed
      FileUtils.mkdir_p(File.dirname(MEMBERS_YML))
      File.write(MEMBERS_YML, "enabled: true\n")
    end
  end

  teardown { File.delete(MEMBERS_YML) if !@members_yml_existed && File.exist?(MEMBERS_YML) }

  test "the members settings page warns when there's no address" do
    SiteSender.stubs(:configured?).returns(false)

    get admin_edit_members_config_path

    assert_response :success
    assert_select "[data-sender-warning]", 1
  end

  test "the members settings page says nothing once an address is set" do
    SiteSender.stubs(:configured?).returns(true)

    get admin_edit_members_config_path

    assert_response :success
    assert_select "[data-sender-warning]", 0
  end

  test "the settings index badges site.yml, where the setting actually lives" do
    with_site_config({})

    get admin_configs_path

    assert_response :success
    assert_select "[data-no-sender]", 1, "one badge, on the file that holds the setting"
    assert_select "tr", text: /site\.yml/ do
      assert_select "[data-no-sender]"
    end
  end

  test "the admin nav dot appears when the only problem is a missing address" do
    # The integrations are reported as fine, so the dot can only come from
    # sender_unconfigured?. Without this the test passes either way — the
    # fixture has no Postmark, so email_unconfigured? lights the dot anyway.
    SiteFeature.stubs(:any_integration_unconfigured?).returns(false)
    with_site_config({})

    get admin_configs_path

    assert_response :success
    assert_select "[title='Some settings need attention']"
  end

  test "the admin nav dot stays away when nothing needs attention" do
    SiteFeature.stubs(:any_integration_unconfigured?).returns(false)
    with_site_config("author_email" => "hello@example.com")

    get admin_configs_path

    assert_response :success
    assert_select "[title='Some settings need attention']", 0
  end

  test "the settings index stays quiet once an address is set" do
    with_site_config("author_email" => "hello@example.com")

    get admin_configs_path

    assert_response :success
    assert_select "[data-no-sender]", 0
  end

  # ── Send test email button ───────────────────────────────────────────────

  test "the test email button is offered once Postmark is connected" do
    PostmarkConfig.any_instance.stubs(:connected?).returns(true)

    get admin_edit_newsletters_config_path

    assert_response :success
    assert_select "a[href=?][data-turbo-method=post]", admin_send_test_email_newsletters_config_path
    assert_select "[data-test-email-disabled]", 0
  end

  test "the test email button is shown disabled before there's a connection" do
    # Greyed rather than hidden, so it's clear the step exists and what has to
    # happen first.
    PostmarkConfig.any_instance.stubs(:connected?).returns(false)

    get admin_edit_newsletters_config_path

    assert_response :success
    assert_select "[data-test-email-disabled]"
    assert_select "a[href=?]", admin_send_test_email_newsletters_config_path, 0
  end

  # ── What the flash claims ────────────────────────────────────────────────

  test "a sandbox server is not described as having delivered anything" do
    # It accepts the message and records it in Activity, but never sends it.
    # "Check your inbox" there sends someone hunting for an email that will
    # never arrive — which is exactly what happened before this.
    with_site_config("author_email" => "hello@example.com")
    PostmarkConfig.any_instance.stubs(:connected?).returns(true)
    PostmarkConfig.any_instance.stubs(:verify_sender!).returns(success: true)
    PostmarkService.stubs(:test_connection).returns(success: true, server: { "DeliveryType" => "Sandbox" })

    post admin_send_test_email_newsletters_config_path

    assert_match(/sandbox/i, flash[:notice])
    assert_match(/nothing was delivered/i, flash[:notice])
    assert_no_match(/if it arrives/i, flash[:notice])
  end

  test "a live server is described as having sent the email" do
    with_site_config("author_email" => "hello@example.com")
    PostmarkConfig.any_instance.stubs(:connected?).returns(true)
    PostmarkConfig.any_instance.stubs(:verify_sender!).returns(success: true)
    PostmarkService.stubs(:test_connection).returns(success: true, server: { "DeliveryType" => "Live" })

    post admin_send_test_email_newsletters_config_path

    assert_match(/if it arrives/i, flash[:notice])
    assert_no_match(/sandbox/i, flash[:notice])
  end

  test "a refusal reports what Postmark said" do
    with_site_config("author_email" => "hello@example.com")
    PostmarkConfig.any_instance.stubs(:connected?).returns(true)
    PostmarkConfig.any_instance.stubs(:verify_sender!)
                  .returns(success: false, error: "not a Sender Signature on your account")

    post admin_send_test_email_newsletters_config_path

    assert_match(/Sender Signature/, flash[:alert])
  end

  # ── Rejected sender ──────────────────────────────────────────────────────

  test "a refused address is explained on both settings pages" do
    with_site_config("author_email" => "hello@example.com")
    PostmarkConfig.current.record_sender_rejection!("not a Sender Signature on your account")

    [ admin_edit_members_config_path, admin_edit_newsletters_config_path ].each do |path|
      get path

      assert_response :success
      assert_select "[data-sender-rejected]", 1, "expected the rejection notice on #{path}"
      assert_select "[data-sender-rejected]", text: /not a Sender Signature/
    end
  end

  test "the rejection notice clears when the address is verified" do
    with_site_config("author_email" => "hello@example.com")
    PostmarkConfig.current.update_columns(sender_verified_address: "hello@example.com", sender_error: nil)

    get admin_edit_newsletters_config_path

    assert_response :success
    assert_select "[data-sender-rejected]", 0
  end

  test "a missing address takes priority over a stale refusal" do
    # Both can be true at once. Telling someone their address is unverified
    # when they haven't set one is the wrong instruction.
    PostmarkConfig.current.record_sender_rejection!("not a Sender Signature")
    with_site_config({})

    get admin_edit_newsletters_config_path

    assert_response :success
    assert_select "[data-sender-rejected]", 0
    assert_select "[data-sender-warning]", 1
  end

  test "the Postmark settings page carries the same warning" do
    SiteSender.stubs(:configured?).returns(false)

    get admin_edit_newsletters_config_path

    assert_response :success
    assert_select "[data-sender-warning]", 1
  end
end
