require "test_helper"
require "ostruct"

class Admin::ConfigsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.take
    sign_in_as(@user)

    # Clean slate for integration records
    StripeConfig.delete_all
    PostmarkConfig.delete_all
    SnipcartConfig.delete_all

    # Ensure feature config files exist so integrations show up.
    # Safe — paths route to tmp/test_site/ under RAILS_ENV=test
    # (see config/application.rb), not the real /site directory.
    ensure_feature_file("members.yml")
    ensure_feature_file("store.yml")
  end

  teardown do
    %w[feeds music].each do |feature|
      path = SiteConfig::FEATURES_PATH.join("#{feature}.yml")
      File.delete(path) if File.exist?(path)
      SiteConfig.reload!("features/#{feature}")
    end
  end

  # ── Index ──────────────────────────────────────────────────────────────────

  test "index lists integrations when features are enabled" do
    get admin_configs_path
    assert_response :success
    assert_select "a[href=?]", admin_edit_payments_config_path
    assert_select "a[href=?]", admin_edit_newsletters_config_path
    assert_select "a[href=?]", admin_edit_snipcart_integration_config_path
  end

  # ── Payments (Stripe) ────────────────────────────────────────────────────

  test "edit_payments renders the integration form" do
    get admin_edit_payments_config_path
    assert_response :success
    assert_select "form[action=?]", admin_payments_config_path
  end

  test "update_payments writes test keys to YAML and syncs" do
    patch admin_payments_config_path, params: {
      test: {
        publishable_key: "pk_test_123",
        secret_key: "sk_test_123",
        webhook_signing_secret: "whsec_test_123"
      }
    }

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
    assert_equal "Stripe configuration saved", flash[:notice]

    # Verify YAML file was written
    path = File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml")
    assert File.exist?(path)
    yaml = YAML.load_file(path)
    assert_equal "pk_test_123", yaml["test"]["publishable_key"]
    assert_equal "sk_test_123", yaml["test"]["secret_key"]

    # Verify StripeConfig picked up the test keys
    stripe = StripeConfig.current
    assert_equal "pk_test_123", stripe.publishable_key_test
    assert_equal "sk_test_123", stripe.secret_key_test
  end

  test "update_payments skips masked placeholder values" do
    # Pre-seed stripe.yml with existing values
    FileUtils.mkdir_p(SiteConfig::INTEGRATIONS_PATH)
    File.write(
      File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml"),
      { "test" => { "publishable_key" => "pk_test_existing", "secret_key" => "sk_test_old" } }.to_yaml
    )

    # Submit placeholder for publishable_key and new secret_key
    patch admin_payments_config_path, params: {
      test: {
        publishable_key: "••••••••••••••••",
        secret_key: "sk_test_new"
      }
    }

    assert_redirected_to admin_edit_payments_config_path(tab: "test")

    # Verify stripe.yml preserves old publishable_key and updates secret_key
    stripe_yaml = YAML.load_file(File.join(SiteConfig::INTEGRATIONS_PATH, "stripe.yml"))
    assert_equal "pk_test_existing", stripe_yaml["test"]["publishable_key"]
    assert_equal "sk_test_new",      stripe_yaml["test"]["secret_key"]
  end

  test "update_payments_live redirects in non-production" do
    patch admin_live_payments_config_path, params: {
      live: { publishable_key: "pk_live_123", secret_key: "sk_live_123" }
    }

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Live keys are only saved in production.", flash[:notice]
  end

  test "update_payments_mode switches mode to live when live keys present" do
    stripe = StripeConfig.current
    stripe.update!(
      publishable_key_live: "pk_live_123",
      secret_key_live: "sk_live_123",
      verified_at: Time.current
    )

    patch admin_mode_payments_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_payments_config_path(tab: "live")
    assert_equal "Payments mode set to Live", flash[:notice]
    assert stripe.reload.mode_live?
  end

  test "update_payments_mode rejects live without live keys" do
    patch admin_mode_payments_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
    assert_equal "Add live keys before switching to Live mode", flash[:error]
    assert StripeConfig.current.mode_test?
  end

  test "disconnect_payments clears all keys" do
    stripe = StripeConfig.current
    stripe.update!(
      publishable_key_test: "pk_test_123",
      secret_key_test: "sk_test_123",
      publishable_key_live: "pk_live_123",
      secret_key_live: "sk_live_123",
      verified_at: Time.current
    )
    StripeConfig.save_test_config("publishable_key" => "pk_test_123")

    delete admin_disconnect_payments_config_path

    assert_redirected_to admin_edit_payments_config_path
    assert_equal "Stripe disconnected. All keys cleared.", flash[:notice]

    stripe.reload
    assert_nil stripe.publishable_key_test
    assert_nil stripe.secret_key_test
    assert_nil stripe.publishable_key_live
    assert_nil stripe.secret_key_live
    assert_nil stripe.verified_at
    assert_not File.exist?(StripeConfig::TEST_CONFIG_PATH)
  end

  test "verify_payments returns json verification status" do
    stripe = StripeConfig.current
    stripe.update!(publishable_key_test: "pk_test_123", secret_key_test: "sk_test_123")

    Stripe::Balance.expects(:retrieve).returns(OpenStruct.new(object: "balance"))

    post admin_verify_payments_config_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json["verified"]
    assert json["verified_at"].present?
    assert_nil json["error"]
  end

  # ── Newsletters (Postmark) ───────────────────────────────────────────────

  test "edit_newsletters renders the integration form" do
    get admin_edit_newsletters_config_path
    assert_response :success
    assert_select "form[action=?]", admin_newsletters_config_path
  end

  test "update_newsletters writes test token to YAML and syncs" do
    patch admin_newsletters_config_path, params: {
      test: { server_token: "test-server-token" }
    }

    assert_redirected_to admin_edit_newsletters_config_path(tab: "test")
    assert_equal "Postmark configuration saved", flash[:notice]

    path = File.join(SiteConfig::INTEGRATIONS_PATH, "postmark.yml")
    assert File.exist?(path)
    yaml = YAML.load_file(path)
    assert_equal "test-server-token", yaml["test"]["server_token"]

    postmark = PostmarkConfig.current
    assert_equal "test-server-token", postmark.test_server_token
  end

  test "update_newsletters_live redirects in non-production" do
    patch admin_live_newsletters_config_path, params: {
      live: { server_token: "live-server-token" }
    }

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Live keys are only saved in production.", flash[:notice]
  end

  test "update_newsletters_mode switches mode to live when live token present" do
    postmark = PostmarkConfig.current
    postmark.update!(server_token: "live-token", verified_at: Time.current)

    patch admin_mode_newsletters_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_newsletters_config_path(tab: "live")
    assert_equal "Email mode set to Live", flash[:notice]
    assert postmark.reload.mode_live?
  end

  test "disconnect_newsletters clears all tokens" do
    postmark = PostmarkConfig.current
    postmark.update!(server_token: "test-token", verified_at: Time.current)
    PostmarkConfig.save_test_config("server_token" => "test-token")

    delete admin_disconnect_newsletters_config_path

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Postmark disconnected. All tokens cleared.", flash[:notice]

    postmark.reload
    assert_nil postmark.server_token
    assert_nil postmark.verified_at
    assert_not File.exist?(PostmarkConfig::TEST_CONFIG_PATH)
  end

  test "regenerate_postmark_webhook_token creates new token" do
    postmark = PostmarkConfig.current
    old_token = postmark.webhook_token

    post admin_regenerate_webhook_token_newsletters_config_path

    assert_redirected_to admin_edit_newsletters_config_path
    assert_equal "Webhook token regenerated. Update the URL in Postmark!", flash[:notice]
    assert_not_equal old_token, postmark.reload.webhook_token
  end

  test "verify_newsletters returns json verification status" do
    postmark = PostmarkConfig.current
    postmark.update!(server_token: "test-token")

    PostmarkService.expects(:test_connection).returns({ success: true })

    post admin_verify_newsletters_config_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json["verified"]
    assert json["verified_at"].present?
    assert_nil json["error"]
  end

  # ── Snipcart (Store) ─────────────────────────────────────────────────────

  test "edit_snipcart renders the integration form" do
    get admin_edit_snipcart_integration_config_path
    assert_response :success
    assert_select "form[action=?]", admin_snipcart_integration_config_path
  end

  test "edit_snipcart renders snippet-only tabs that work locally" do
    get admin_edit_snipcart_integration_config_path

    assert_response :success
    # Tabs renamed, both usable locally (no production gate, no masked inputs).
    assert_select "button[data-tabs-panel=?]", "test", text: /Local\/Test/
    assert_select "button[data-tabs-panel=?]", "live", text: /Live\/Static Site/
    assert_select "textarea[name=?]", "test[snippet]"
    assert_select "textarea[name=?]", "live[snippet]"
    # No leftover secret-key inputs.
    assert_select "input[name=?]", "test[secret_key]", count: 0
    assert_select "input[name=?]", "live[secret_key]", count: 0
  end

  test "update_snipcart writes the test snippet to YAML and syncs" do
    patch admin_snipcart_integration_config_path, params: {
      test: { snippet: "<div>test</div>" }
    }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "test")
    assert_equal "Store (Snipcart) Test configuration saved", flash[:notice]

    path = File.join(SiteConfig::INTEGRATIONS_PATH, "snipcart.yml")
    assert File.exist?(path)
    assert_equal "<div>test</div>", YAML.load_file(path)["test"]["snippet"]
    assert_equal "<div>test</div>", SnipcartConfig.current.snippet_test
  end

  # Snipcart's live snippet is a public key, so — unlike Stripe/Postmark live
  # keys — it saves locally with no production gate. It's what the local store
  # and the static-site build both run on.
  test "update_snipcart_live saves the live snippet locally, no production gate" do
    patch admin_live_snipcart_integration_config_path, params: {
      live: { snippet: "<div>live</div>" }
    }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "live")
    assert_equal "Snipcart Live & Static Site configuration saved", flash[:notice]
    assert_equal "<div>live</div>", SnipcartConfig.current.snippet_live
  end

  # The snippets are public and shown in full, so blanking the field clears it
  # (they don't behave like masked secret fields, where blank = "unchanged").
  test "update_snipcart clears the test snippet when submitted blank" do
    SnipcartConfig.save_test_config("snippet" => "<div>old</div>")

    patch admin_snipcart_integration_config_path, params: { test: { snippet: "" } }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "test")
    assert SnipcartConfig.current.snippet_test.blank?, "test snippet cleared"
  end

  test "update_snipcart_live clears the live snippet when submitted blank" do
    SnipcartConfig.save_live_snippet("<div>old</div>")

    patch admin_live_snipcart_integration_config_path, params: { live: { snippet: "" } }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "live")
    assert SnipcartConfig.current.snippet_live.blank?, "live snippet cleared"
  end

  test "update_snipcart_mode switches to live once the live snippet is present" do
    SnipcartConfig.save_live_snippet("<div>live</div>")

    patch admin_mode_snipcart_integration_config_path, params: { mode: "live" }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "live")
    assert_equal "Store mode set to Live", flash[:notice]
    assert SnipcartConfig.current.mode_live?
  end

  test "disconnect_snipcart clears the snippets and verification" do
    SnipcartConfig.save_live_snippet("<div>live</div>")
    SnipcartConfig.save_test_config("snippet" => "<div>test</div>")
    SnipcartConfig.current.update!(verified_at: Time.current)

    delete admin_disconnect_snipcart_integration_config_path

    assert_redirected_to admin_edit_snipcart_integration_config_path
    assert_equal "Snipcart disconnected. All keys cleared.", flash[:notice]

    assert_nil SnipcartConfig.current.verified_at
    assert_not File.exist?(SnipcartConfig::TEST_CONFIG_PATH)
  end

  test "verify_snipcart returns json verification status" do
    SnipcartConfig.current.update!(verified_at: Time.current)
    SnipcartConfig.any_instance.stubs(:verify!).returns(true)

    post admin_verify_snipcart_integration_config_path

    assert_response :success
    json = JSON.parse(response.body)
    assert json["verified"]
    assert json["verified_at"].present?
    assert_nil json["error"]
  end

  # ── Edge cases ───────────────────────────────────────────────────────────

  test "update_payments_mode rejects invalid mode" do
    patch admin_mode_payments_config_path, params: { mode: "invalid" }

    assert_redirected_to admin_edit_payments_config_path(tab: "test")
    assert_equal "Invalid mode: \"invalid\"", flash[:error]
  end

  test "update_newsletters_mode rejects invalid mode" do
    patch admin_mode_newsletters_config_path, params: { mode: "staging" }

    assert_redirected_to admin_edit_newsletters_config_path(tab: "test")
    assert_equal "Invalid mode: \"staging\"", flash[:error]
  end

  test "update_snipcart_mode rejects invalid mode" do
    patch admin_mode_snipcart_integration_config_path, params: { mode: "staging" }

    assert_redirected_to admin_edit_snipcart_integration_config_path(tab: "test")
    assert_equal "Invalid mode: \"staging\"", flash[:error]
  end

  test "unauthenticated user is redirected from integration pages" do
    # Clear the admin session cookie directly
    cookies.delete("session_id")
    get admin_edit_payments_config_path
    assert_redirected_to new_session_path
  end

  test "site config editor renders the nightly-updates toggle" do
    FileUtils.mkdir_p(File.dirname(SiteConfig::SITE_FILE))
    File.write(SiteConfig::SITE_FILE,
               { "title" => "T", "update_channel" => "nightly" }.to_yaml)

    get admin_edit_site_config_path

    assert_response :success
    # Nightly toggle maps to stable/nightly instead of true/false
    assert_select "input[data-config-field=?][data-on-value=?][data-off-value=?]",
                  "update_channel", "nightly", "stable"
  end

  test "content config editor renders the search toggle" do
    FileUtils.mkdir_p(File.dirname(SiteConfig::CONTENT_FILE))
    File.write(SiteConfig::CONTENT_FILE,
               { "search" => { "all_pages" => true } }.to_yaml)

    get admin_edit_content_config_path

    assert_response :success
    # Search moved out of site.yml into content.yml (nested under `search`).
    assert_select "input[data-config-field=?][type=checkbox]", "search.all_pages"
  end

  # ── Custom feeds ─────────────────────────────────────────────────────────

  test "new_feeds_setup creates feeds.yml with an example and opens the editor" do
    feeds = SiteConfig::FEATURES_PATH.join("feeds.yml")
    File.delete(feeds) if File.exist?(feeds)

    get new_feeds_setup_admin_configs_path

    assert File.exist?(feeds), "feeds.yml is created"
    assert_includes File.read(feeds), "articles", "seeded with an example feed"
    assert_redirected_to admin_edit_feeds_config_path
  end

  test "the Enable Custom Feeds button shows while the feature is off" do
    feeds = SiteConfig::FEATURES_PATH.join("feeds.yml")
    File.delete(feeds) if File.exist?(feeds)

    get admin_configs_path

    assert_response :success
    assert_select "a[href=?]", new_feeds_setup_admin_configs_path
  end

  test "index lists feeds.yml under Features once enabled" do
    ensure_feature_file("feeds.yml")

    get admin_configs_path

    assert_response :success
    assert_select "a[href=?]", admin_edit_feeds_config_path
  end

  test "update_feeds saves a valid YAML mapping" do
    ensure_feature_file("feeds.yml")

    patch admin_feeds_config_path, params: { content: "music:\n  source: posts\n  tags: music\n" }

    assert_redirected_to admin_configs_path
    assert_includes File.read(SiteConfig::FEATURES_PATH.join("feeds.yml")), "music"
  end

  test "update_feeds rejects a non-mapping document without writing it" do
    ensure_feature_file("feeds.yml")
    before = File.read(SiteConfig::FEATURES_PATH.join("feeds.yml"))

    patch admin_feeds_config_path, params: { content: "- just\n- a\n- list\n" }

    assert_response :unprocessable_entity
    assert_equal before, File.read(SiteConfig::FEATURES_PATH.join("feeds.yml")), "bad input is not written"
  end

  # ── Music ──────────────────────────────────────────────────────────────────

  test "new_music_setup creates music.yml and opens the editor" do
    music = SiteConfig::FEATURES_PATH.join("music.yml")
    File.delete(music) if File.exist?(music)

    get new_music_setup_admin_configs_path

    assert File.exist?(music), "music.yml is created"
    assert_includes File.read(music), "singles", "seeded with the default release"
    assert_redirected_to admin_edit_music_config_path
  end

  # The seed lived in a heredoc here while lib/site_templates/features/music/
  # held a stale copy with the releases at the top level and no `releases:` key
  # — which parses to {"singles" => nil}, so ReleaseConfig resolves nothing.
  # Now that the template is the source of truth, check what it seeds actually
  # resolves rather than just that the file has words in it.
  test "the seeded music.yml resolves as releases, not as bare top-level keys" do
    music = SiteConfig::FEATURES_PATH.join("music.yml")
    File.delete(music) if File.exist?(music)

    get new_music_setup_admin_configs_path

    assert_equal [ ReleaseConfig::DEFAULT_RELEASE ], ReleaseConfig.release_keys,
      "a new post defaults to release: #{ReleaseConfig::DEFAULT_RELEASE}, so it has to exist — and nothing else ships"
    assert_equal "Singles", ReleaseConfig.get("singles")["title"]
    assert_equal "free", ReleaseConfig.audience_for("singles"), "inherited from the global default"
  end

  test "the Enable Music button shows while the feature is off" do
    music = SiteConfig::FEATURES_PATH.join("music.yml")
    File.delete(music) if File.exist?(music)

    get admin_configs_path

    assert_response :success
    assert_select "a[href=?]", new_music_setup_admin_configs_path
  end

  test "index lists music.yml under Features once enabled" do
    ensure_feature_file("music.yml")

    get admin_configs_path

    assert_response :success
    assert_select "a[href=?]", admin_edit_music_config_path
  end

  test "edit_music renders a form field for every schema field" do
    get new_music_setup_admin_configs_path
    get admin_edit_music_config_path

    assert_response :success
    MusicConfigSchema.release_fields.each do |field|
      # A checkbox renders twice on purpose — see the unticking test below.
      expected = field[:kind] == :checkbox ? 2 : 1
      assert_select "[name=?]", "releases[0][#{field[:key]}]", { count: expected },
        "no input for #{field[:key]}"
    end
    assert_select "[name=?]", "releases[0][key]", { count: 1 }, "the release key is editable"
    assert_select "[name=?]", "music_globals[artist]"
  end

  # Audience only means something with paid memberships configured — the same
  # test the post and page editors use before showing their own audience field.
  # Off, it's a control that silently does nothing.
  test "the audience field is hidden until memberships are configured" do
    get new_music_setup_admin_configs_path

    SiteFeature.stubs(:memberships_enabled?).returns(false)
    get admin_edit_music_config_path
    assert_select "[name=?]", "releases[0][audience]", count: 0

    SiteFeature.stubs(:memberships_enabled?).returns(true)
    get admin_edit_music_config_path
    assert_select "[name=?]", "releases[0][audience]", count: 1
  end

  test "update_music writes form fields under releases:, dropping blanks" do
    get new_music_setup_admin_configs_path

    patch admin_music_config_path, params: {
      music_globals: { "artist" => "Yitta Bitta", "audience" => "free" },
      releases: { "0" => {
        "original_key" => "singles", "key" => "singles",
        "title" => "Singles", "synopsis" => "Individual tracks.",
        "genre" => "", "label" => "", "copyright" => "", "cover" => "", "artist" => "", "release_date" => ""
      } }
    }

    written = YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))
    assert_equal "Yitta Bitta", written["artist"]
    assert_equal({ "title" => "Singles", "synopsis" => "Individual tracks." }, written["releases"]["singles"],
      "blank fields are left out rather than written as empty strings")
    assert_includes ReleaseConfig.release_keys, "singles", "and it still resolves"
  end

  test "update_music renames a release when the key input changes" do
    get new_music_setup_admin_configs_path

    patch admin_music_config_path, params: {
      releases: { "0" => { "original_key" => "singles", "key" => "B Sides", "title" => "B Sides" } }
    }

    keys = YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))["releases"].keys
    assert_equal [ "b-sides" ], keys, "the typed key is slugified"
  end

  test "a release row with a blank key keeps the one it had" do
    get new_music_setup_admin_configs_path

    patch admin_music_config_path, params: {
      releases: { "0" => { "original_key" => "singles", "key" => "", "title" => "Singles" } }
    }

    assert_includes YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))["releases"].keys, "singles"
  end

  # Adding and removing releases is client-side — the form posts whatever rows
  # are on the page and update_music rebuilds the list from them. So a row the
  # browser added saves as a new release, and one it removed simply isn't
  # posted. These two tests stand in for that round trip.
  test "a posted row that isn't in the file yet is added" do
    get new_music_setup_admin_configs_path

    patch admin_music_config_path, params: {
      releases: {
        "0" => { "original_key" => "singles", "key" => "singles", "title" => "Singles" },
        "1" => { "original_key" => "", "key" => "summer-release", "title" => "Summer Release" }
      }
    }

    releases = YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))["releases"]
    assert_equal %w[singles summer-release], releases.keys
    assert_equal "Summer Release", releases["summer-release"]["title"]
  end

  test "a release whose row is not posted is dropped" do
    get new_music_setup_admin_configs_path
    patch admin_music_config_path, params: {
      releases: {
        "0" => { "original_key" => "singles", "key" => "singles", "title" => "Singles" },
        "1" => { "original_key" => "", "key" => "b-sides", "title" => "B Sides" }
      }
    }
    assert_equal %w[singles b-sides], YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))["releases"].keys

    patch admin_music_config_path, params: {
      releases: { "0" => { "original_key" => "singles", "key" => "singles", "title" => "Singles" } }
    }

    assert_equal %w[singles], YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))["releases"].keys
  end

  # A lone checkbox posts nothing when unticked, so the old value would stick
  # and the feed could never be switched off from the form. The hidden field
  # before it is what makes unticking mean false.
  test "the feed checkbox can be unticked" do
    get new_music_setup_admin_configs_path
    patch admin_music_config_path, params: {
      releases: { "0" => { "original_key" => "singles", "key" => "singles", "title" => "Singles",
                           "synopsis" => "S", "cover" => "/media/images/c.jpg", "feed" => "true" } }
    }
    assert ReleaseConfig.feed_enabled?("singles"), "on first"

    patch admin_music_config_path, params: {
      releases: { "0" => { "original_key" => "singles", "key" => "singles", "title" => "Singles",
                           "synopsis" => "S", "cover" => "/media/images/c.jpg", "feed" => "false" } }
    }

    assert_not ReleaseConfig.feed_enabled?("singles")
    assert_not YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))["releases"]["singles"].key?("feed"),
      "an off feed isn't written at all"
  end

  # The anchor a track's "Edit release →" link jumps to.
  test "each release renders an id the metadata editor can link to" do
    get new_music_setup_admin_configs_path
    get admin_edit_music_config_path

    assert_select "#release-singles", count: 1
  end

  # The clone source for + New Release. Its inputs carry __INDEX__ so the
  # controller can renumber them; without the <template> wrapper the browser
  # would post them as a real release on every save.
  test "the form ships a blank release template for the add button" do
    get new_music_setup_admin_configs_path
    get admin_edit_music_config_path

    assert_select "template[data-music-releases-target=?]", "template" do
      assert_select "[name=?]", "releases[__INDEX__][key]"
      assert_select "[name=?]", "releases[__INDEX__][title]"
    end
  end

  # The YAML toggle posts to the same action. Without the `content` branch
  # taking precedence, a YAML save would be read as a form save with no
  # releases at all and wipe the file.
  test "the YAML escape hatch still saves, and doesn't go through the form path" do
    get new_music_setup_admin_configs_path

    patch admin_music_config_path, params: { content: "artist: Me\nreleases:\n  winter:\n    title: Winter\n" }

    written = YAML.safe_load(File.read(SiteConfig::FEATURES_PATH.join("music.yml")))
    assert_equal [ "winter" ], written["releases"].keys
    assert_equal "Me", written["artist"]
  end

  test "update_music saves a valid YAML mapping" do
    ensure_feature_file("music.yml")

    patch admin_music_config_path, params: { content: "winter:\n  title: Winter\n  release_date: 2026-12-01\n" }

    assert_redirected_to admin_configs_path
    assert_includes File.read(SiteConfig::FEATURES_PATH.join("music.yml")), "Winter"
  end

  # ── Raw YAML fallback ──────────────────────────────────────────────────────

  test "a structured editor with malformed YAML redirects to the raw editor" do
    File.write(SiteConfig::FEATURES_PATH.join("store.yml"), "enabled: true\n- broken\n")

    get admin_edit_store_config_path

    assert_redirected_to admin_edit_raw_config_path(type: "features/store")
  end

  test "edit_raw shows the offending file's content" do
    File.write(SiteConfig::FEATURES_PATH.join("store.yml"), "enabled: true\n- broken\n")

    get admin_edit_raw_config_path(type: "features/store")

    assert_response :success
    assert_select "textarea", /broken/
  end

  test "update_raw writes valid YAML and returns to the settings form" do
    ensure_feature_file("store.yml")

    patch admin_raw_config_path, params: { type: "features/store", content: "enabled: true\ncurrency: usd\n" }

    assert_redirected_to admin_edit_store_config_path
    assert_includes File.read(SiteConfig::FEATURES_PATH.join("store.yml")), "usd"
  end

  test "update_raw re-renders when the YAML still won't parse" do
    ensure_feature_file("store.yml")

    patch admin_raw_config_path, params: { type: "features/store", content: "ok: true\n- nope\n" }

    assert_response :unprocessable_entity
  end

  test "the raw editor rejects a config type not on the whitelist" do
    get admin_edit_raw_config_path(type: "etc/passwd")

    assert_redirected_to admin_configs_path
  end

  # ── Members: Display section ───────────────────────────────────────────────

  # Every members.yml written before this setting existed has no display key at
  # all, so the section has to be seeded on the way into the form or the option
  # is invisible to every site that already runs members.
  test "the members editor shows Display for a members.yml that has no display key" do
    get admin_edit_members_config_path

    assert_response :success
    assert_includes response.body, "Display"
    assert_select "input[type=checkbox][data-config-field='display.always_show_member_icon']", 1
  end

  test "the icon setting starts unchecked" do
    get admin_edit_members_config_path

    assert_select "input[data-config-field='display.always_show_member_icon']", 1
    assert_select "input[data-config-field='display.always_show_member_icon'][checked]", 0,
      "opt-in — an existing site's header must not change on upgrade"
  end

  test "a members.yml that turns the icon on renders it checked" do
    File.write(SiteConfig::FEATURES_PATH.join("members.yml"),
               "display:\n  always_show_member_icon: true\npayments:\n  enabled: false\n")

    get admin_edit_members_config_path

    assert_select "input[data-config-field='display.always_show_member_icon'][checked]", 1,
      "a saved setting that renders unchecked reads exactly like the save being ignored"
  end

  # It's a yes/no, and the two-option select the other booleans use makes a
  # yes/no look like a decision between two things.
  test "the icon setting is a checkbox, not a select" do
    get admin_edit_members_config_path

    assert_select "input[type=checkbox][data-config-field='display.always_show_member_icon']", 1
    assert_select "select[data-config-field='display.always_show_member_icon']", 0
  end

  # The form posts YAML that formToYaml built from the checkbox, so this is the
  # shape the save path actually receives. Worth asserting end to end: a setting
  # that renders correctly but doesn't persist reads to the user as the save
  # being ignored, which is exactly how the docs.roe select failed.
  test "turning the icon on saves and reads back as on" do
    patch admin_members_config_path,
          params: { content: "display:\n  always_show_member_icon: true\npayments:\n  enabled: false\n" }

    assert SiteFeature.always_show_member_icon?, "saved, then read back as off"

    patch admin_members_config_path,
          params: { content: "display:\n  always_show_member_icon: false\npayments:\n  enabled: false\n" }

    assert_not SiteFeature.always_show_member_icon?, "turning it back off has to stick too"
  end

  private

  def ensure_feature_file(filename)
    features_path = SiteConfig::FEATURES_PATH
    FileUtils.mkdir_p(features_path)
    path = features_path.join(filename)

    case filename
    when "members.yml"
      File.write(path, <<~YAML)
        payments:
          enabled: true
        newsletter:
          enabled: true
      YAML
    else
      File.write(path, "{}")
    end

    # Sync to SiteConfig so current() reads from the record, not stale cache
    type = "features/#{filename.sub(/\.yml$/, "")}"
    SiteConfig.sync_from_file(type)
    SiteConfig.reload!(type)
  end

  # ── Podcast: unsaved-edit hazards ──────────────────────────────────────────

  def write_podcast(shows)
    path = SiteConfig::FEATURES_PATH.join("podcast.yml")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, shows.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.sync_from_file("features/podcast")
    SiteConfig.reload!("features/podcast")
  end

  def a_show(title)
    PodcastConfig.default_entry.merge("title" => title, "description" => "About #{title}")
  end

  # ADD NEW used to POST, rewrite podcast.yml and reload — losing every unsaved
  # edit on the page. It's a client-side clone now, so it must not be a form.
  test "ADD NEW no longer submits a form" do
    write_podcast("show-one" => a_show("Show One"))

    get admin_edit_podcast_config_path

    assert_response :success
    assert_select "button[data-action=?]", "podcast-entries#add"
    assert_select "form[action=?]", add_podcast_admin_configs_path, { count: 0 },
      "adding a show shouldn't navigate"
  end

  # The clone source. With no panel to copy, the controller falls back to the
  # server action — so the path has to reach the page.
  test "the podcast form carries a panel to clone and a fallback path" do
    write_podcast("show-one" => a_show("Show One"))

    get admin_edit_podcast_config_path

    assert_select "[data-tabs-target=?][data-tabs-panel=?]", "panel", "show-one"
    assert_select "[data-podcast-entries-add-path-value=?]", add_podcast_admin_configs_path
  end

  # Seeding rewrites the show and reloads. Turbo's submit doesn't fire
  # turbo:before-visit, so the editor's own guard never saw it.
  test "seeding from RSS is guarded, and the modal is on the page" do
    write_podcast("show-one" => a_show("Show One"))

    get admin_edit_podcast_config_path

    assert_select "form[action=?][data-action=?]",
      admin_seed_podcast_config_from_rss_path, "submit->config-guard#guard"
    assert_select "[data-config-guard-target=?]", "modal", count: 1
    assert_select "[data-controller=?]", "config-guard"
  end

  # The server action stays as the empty-file fallback, so it has to keep working.
  test "add_podcast still appends a show for a config with none" do
    write_podcast({})

    post add_podcast_admin_configs_path

    assert_equal %w[new-podcast],
      YAML.load_file(SiteConfig::FEATURES_PATH.join("podcast.yml")).keys
  end

  # Only ADD went client-side. Removing a show can also delete its draft
  # episodes, which isn't a config edit and shouldn't wait for Save.
  test "removing a show is still a server action" do
    write_podcast("show-one" => a_show("Show One"))

    get admin_edit_podcast_config_path

    assert_select "form[action=?]", delete_podcast_entry_admin_configs_path(key: "show-one")
  end

  # ── Retired settings cleanup ───────────────────────────────────────────────

  def write_defaults(filename, yaml)
    FileUtils.mkdir_p(SiteConfig::DEFAULTS_PATH)
    path = SiteConfig::DEFAULTS_PATH.join(filename)
    File.write(path, yaml)
    SiteConfig.sync_from_file("defaults/#{filename.sub(/\.yml$/, "")}")
    path
  end

  # Button templates were replaced by the builders. A file written before that
  # still has the keys; the form should explain them rather than render them as
  # editable settings that do nothing.
  test "a leftover button template is explained, not rendered as a field" do
    write_defaults("collections.yml", "default_limit: 10\nbutton_template: |-\n  limit: 5\n")

    get admin_edit_collections_config_path

    assert_response :success
    assert_select "textarea[data-config-field=?]", "button_template", { count: 0 },
      "a dead setting shouldn't look editable"
    assert_select "form[action=?]", admin_cleanup_config_path(type: "collections")
    assert_match(/limit/, response.body)
  end

  test "a clean file shows no cleanup notice" do
    write_defaults("collections.yml", "default_limit: 10\n")

    get admin_edit_collections_config_path

    assert_select "form[action=?]", admin_cleanup_config_path(type: "collections"), count: 0
  end

  test "cleanup removes the retired keys and keeps the defaults" do
    path = write_defaults("collections.yml", "default_limit: 10\nbutton_template: |-\n  limit: 5\n")

    post admin_cleanup_config_path(type: "collections")

    assert_redirected_to admin_edit_collections_config_path
    assert_equal({ "default_limit" => 10 }, YAML.safe_load(File.read(path)))
  end

  test "cleanup works on the nested cards file too" do
    path = write_defaults("cards.yml",
      "post-link:\n  default_style: small\npost_link_button_template: |-\n  style: small\n")

    post admin_cleanup_config_path(type: "cards")

    assert_equal({ "post-link" => { "default_style" => "small" } }, YAML.safe_load(File.read(path)))
  end

  test "cleanup on an unknown config type is refused" do
    post admin_cleanup_config_path(type: "site")

    assert_redirected_to admin_configs_path
  end

  test "cleanup on an already-clean file says so rather than erroring" do
    write_defaults("collections.yml", "default_limit: 10\n")

    post admin_cleanup_config_path(type: "collections")

    assert_redirected_to admin_edit_collections_config_path
    assert_match(/already up to date/, flash[:notice])
  end
end
