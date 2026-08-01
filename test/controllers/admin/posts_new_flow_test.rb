# frozen_string_literal: true

require "test_helper"

# The NEW POST form asks for the least Roe needs to write a working post:
# filename, an optional title, the type, and that type's create_fields. What
# comes back is a file whose body already renders — a player with audio to
# play, a track list that knows what to gather.
class Admin::PostsNewFlowTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    @created.to_a.each { |f| File.delete(f) if File.exist?(f) }
  end

  def create_post(params)
    @created ||= []
    @created << File.join(RoeSitePaths::SITE_PATH, "posts", "#{params[:filename]}.md")
    post admin_posts_path, params: params
  end

  def file_for(filename)
    File.read(File.join(RoeSitePaths::SITE_PATH, "posts", "#{filename}.md"))
  end

  # --- the form ------------------------------------------------------------

  test "the form offers a title, a type, and each type's create fields" do
    get new_admin_post_path

    assert_response :success
    assert_includes response.body, 'data-controller="new-content"'
    assert_includes response.body, 'data-new-content-target="title"'
    assert_includes response.body, 'data-new-content-target="postType"'
    # Audio's create field, in its own hidden group.
    assert_includes response.body, 'data-post-type="audio"'
    assert_includes response.body, 'name="fields[audio]"'
  end

  # Audience follows members being enabled, NOT paid memberships being
  # configured — a site with members but no payments still chooses who sees a
  # post. The form gate and the server whitelist have to agree, or the field
  # renders and its value is then silently dropped.
  test "audience shows whenever members is enabled, defaulting to everyone" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteFeature.stubs(:memberships_enabled?).returns(false)

    get new_admin_post_path

    assert_response :success
    assert_includes response.body, 'name="fields[audience]"'
    assert_match(/name="fields\[audience\]".*?<option value="everyone"/m, response.body,
      "everyone is the first option, so it's the default")
  end

  test "audience is written to the new post" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteFeature.stubs(:memberships_enabled?).returns(false)
    create_post(filename: "flow-audience", post_type: "article", fields: { audience: "paid" })

    assert_includes file_for("flow-audience"), 'audience: "paid"'
  end

  test "audience is not offered when members is off" do
    SiteFeature.stubs(:members_enabled?).returns(false)

    get new_admin_post_path
    assert_not_includes response.body, 'name="fields[audience]"'
  end

  # --- filename / title derive from each other -----------------------------

  # A title-only submission used to write "posts/.md". File.extname reads that
  # as having no extension, so the front matter parser couldn't pick a syntax
  # and died on nil.to_sym — surfacing later as a YAML parse error in the editor.
  test "a blank filename is derived from the title" do
    @created ||= []
    @created << File.join(RoeSitePaths::SITE_PATH, "posts", "my-podcast-episode.md")

    post admin_posts_path, params: { filename: "", title: "My Podcast Episode", post_type: "article" }

    assert File.exist?(File.join(RoeSitePaths::SITE_PATH, "posts", "my-podcast-episode.md")),
      "the filename should follow from the title"
    assert_not File.exist?(File.join(RoeSitePaths::SITE_PATH, "posts", ".md")),
      "a dotfile must never be written"
  end

  test "a blank filename and title is refused rather than written" do
    post admin_posts_path, params: { filename: "", title: "", post_type: "article" }

    assert_response :unprocessable_entity
    assert_not File.exist?(File.join(RoeSitePaths::SITE_PATH, "posts", ".md"))
  end

  # --- uniqueness warnings -------------------------------------------------

  test "check_unique reports a scoped clash and names the conflict" do
    @created ||= []
    @created << File.join(RoeSitePaths::SITE_PATH, "posts", "uniq-ep.md")
    File.write(File.join(RoeSitePaths::SITE_PATH, "posts", "uniq-ep.md"),
      "---\ntitle: \"Ep One\"\nurl_name: uniq-ep\nstatus: published\n" \
      "post_type: podcast\npodcast: showa\nepisode_number: '1'\n---\nx\n")
    ContentSync.sync_file(File.join(RoeSitePaths::SITE_PATH, "posts", "uniq-ep.md"))

    get check_unique_admin_posts_path, params: { field: "episode_number", value: "1", scopes: { podcast: "showa" } }
    assert_response :success
    body = JSON.parse(response.body)
    assert body["taken"]
    assert_equal "Ep One", body["conflict"]

    get check_unique_admin_posts_path, params: { field: "episode_number", value: "1", scopes: { podcast: "showb" } }
    assert_not JSON.parse(response.body)["taken"], "another show's episode 1 is not a clash"
  end

  test "the form wires the advisory check onto numbered fields" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    SiteFeature.stubs(:music_enabled?).returns(true)
    Rails.cache.delete("post_type_options/v2")

    get new_admin_post_path

    assert_includes response.body, 'data-action="input->new-content#checkUnique"'
    assert_includes response.body, 'data-unique-field="episode_number"'
    assert_includes response.body, 'data-unique-scope-fields="podcast,season"'
    assert_includes response.body, "data-unique-warning"
  end

  # --- media picker --------------------------------------------------------

  test "media fields get a picker button wired to the right media type" do
    get new_admin_post_path

    assert_response :success
    assert_includes response.body, 'data-action="click->new-content#openPicker"'
    assert_includes response.body, 'data-media-type="audio"'
    assert_includes response.body, 'data-media-type="video"'
    assert_includes response.body, 'data-field-id="fields_audio_audio"'
    assert_includes response.body, 'data-new-content-target="pickerModal"'
    assert_includes response.body, 'data-new-content-target="pickerContent"'
  end

  test "a non-media field gets no picker" do
    get new_admin_post_path

    assert_not_includes response.body, 'data-field-id="fields_music_track_number"'
  end

  # --- title ---------------------------------------------------------------

  test "a blank title falls back to the one derived from the filename" do
    create_post(filename: "my-new-post", title: "", post_type: "article")

    assert_includes file_for("my-new-post"), 'title: "My New Post"'
  end

  test "a supplied title wins over the derived one" do
    create_post(filename: "my-new-post-2", title: "Something Else", post_type: "article")

    assert_includes file_for("my-new-post-2"), "Something Else"
    assert_not_includes file_for("my-new-post-2"), 'title: "My New Post 2"'
  end

  # --- type + create fields → a body that renders --------------------------

  test "an audio post arrives with its audio set and a player in the body" do
    create_post(filename: "flow-audio", post_type: "audio", fields: { audio: "/media/audio/a.mp3" })

    content = file_for("flow-audio")
    assert_includes content, 'post_type: "audio"'
    assert_includes content, 'audio: "/media/audio/a.mp3"'
    assert_includes content, "```card"
    assert_includes content, "type: player"
  end

  test "a music track arrives with a player and its release's track list" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    create_post(filename: "flow-music", post_type: "music",
                fields: { audio: "/media/audio/t.mp3", release: "summer-ep", track_number: "3" })

    content = file_for("flow-music")
    assert_includes content, 'post_type: "music"'
    assert_includes content, 'release: "summer-ep"'
    assert_includes content, 'track_number: "3"'
    assert_includes content, "template: playlist"
    assert_includes content, "order: track_number"
  end

  test "blank create fields are left out of the frontmatter" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    create_post(filename: "flow-blank", post_type: "music",
                fields: { audio: "/media/audio/t.mp3", release: "", track_number: "" })

    content = file_for("flow-blank")
    assert_includes content, 'audio: "/media/audio/t.mp3"'
    assert_not_includes content, "track_number:", "a blank number isn't written"
  end

  # A single is still part of something — otherwise it gets no track list and
  # nothing gathers it.
  test "a music track with no release falls back to singles" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    create_post(filename: "flow-single", post_type: "music",
                fields: { audio: "/media/audio/s.mp3", release: "" })

    content = file_for("flow-single")
    assert_includes content, 'release: "singles"'
    assert_includes content, "template: playlist", "singles still get a track list"
    assert_includes content, "release: singles"
  end

  test "an explicit release is left alone" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    create_post(filename: "flow-explicit", post_type: "music",
                fields: { audio: "/media/audio/s.mp3", release: "summer-ep" })

    assert_includes file_for("flow-explicit"), 'release: "summer-ep"'
  end

  test "a post still defaults to draft" do
    create_post(filename: "flow-draft", post_type: "article")

    assert_includes file_for("flow-draft"), 'status: "draft"'
  end

  # --- the whitelist -------------------------------------------------------

  test "fields the chosen type doesn't declare are ignored" do
    create_post(filename: "flow-inject", post_type: "article",
                fields: { audio: "/media/audio/nope.mp3", status: "published" })

    content = file_for("flow-inject")
    assert_not_includes content, "nope.mp3", "article declares no audio create field"
    assert_includes content, 'status: "draft"', "status isn't a create field and can't be forced"
  end

  test "a feature-gated type can't be chosen while its feature is off" do
    SiteFeature.stubs(:music_enabled?).returns(false)
    create_post(filename: "flow-gated", post_type: "music",
                fields: { audio: "/media/audio/t.mp3" })

    content = file_for("flow-gated")
    assert_not_includes content, 'post_type: "music"'
    assert_not_includes content, "/media/audio/t.mp3",
      "music's create fields go with it"
  end

  test "an unknown post_type is ignored rather than written" do
    create_post(filename: "flow-bogus", post_type: "wingdings")

    assert_not_includes file_for("flow-bogus"), "wingdings"
  end

  # --- the JS mirror -------------------------------------------------------

  # The form fills the filename in from the title as you type, and the server
  # derives the same thing when the field is left blank. If they disagree, the
  # field shows one name and a different file gets written.
  test "the JS filename derivation matches the server's" do
    js = File.read(Rails.root.join("app/javascript/controllers/new_content_controller.js"))
    assert_includes js, "filenameFrom", "the derivation lives in filenameFrom()"

    controller = Admin::PostsController.new
    {
      "My New Post"      => "my-new-post",
      "Don't Stop"       => "don-t-stop",
      "  Spaced  Out  "  => "spaced-out",
      "Episode 12: Live" => "episode-12-live"
    }.each do |title, expected|
      derived = controller.send(:sanitize_filename, title.strip.parameterize)
      assert_equal expected, derived,
        "Ruby side changed; update filenameFrom() in new_content_controller.js to match"
    end
  end
end
