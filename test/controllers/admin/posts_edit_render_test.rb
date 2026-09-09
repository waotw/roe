# frozen_string_literal: true

require "test_helper"

# The editor actions row is a shared partial rendered twice — in-flow at the top
# and inside the sticky bottom drawer. Lock that the edit view + partial render.
class Admin::PostsEditRenderTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    %w[edit-render.md edit-music.md uniq-a.md uniq-b.md].each do |f|
      File.delete(File.join(RoeSitePaths::SITE_PATH, "posts", f)) rescue nil
    end
  end

  # Pre-save (as you type) is handled by the unique-field controller; this is
  # the after-save half — an existing clash is visible the moment the editor
  # opens, without touching anything.
  test "an existing episode-number clash is shown on load, and never blocks" do
    dir = File.join(RoeSitePaths::SITE_PATH, "posts")
    [ %w[uniq-a First], %w[uniq-b Second] ].each do |slug, title|
      path = File.join(dir, "#{slug}.md")
      File.write(path, "---\ntitle: \"#{title}\"\nurl_name: #{slug}\nstatus: published\n" \
                       "post_type: podcast\npodcast: showa\nepisode_number: '4'\n---\nx\n")
      ContentSync.sync_file(path)
    end
    record = Post.find_by("json_extract(metadata, '$.url_name') = ?", "uniq-b")

    get edit_admin_post_path(record)

    assert_response :success
    assert_includes response.body, 'data-controller="unique-field"'
    assert_includes response.body, "Already used by"
    assert_includes response.body, "First", "the clashing post is named"
    # Both scope fields and the post's own url_name ride along, so the live
    # check stays scoped to show + season and the post can't flag itself.
    assert_match(/data-unique-field-scope-fields-value="[^"]*podcast[^"]*season/, response.body)
    assert_includes response.body, 'data-unique-field-exclude-value="uniq-b"'
  end

  test "a unique episode number shows no warning" do
    dir = File.join(RoeSitePaths::SITE_PATH, "posts")
    path = File.join(dir, "uniq-a.md")
    File.write(path, "---\ntitle: \"Only\"\nurl_name: uniq-a\nstatus: published\n" \
                     "post_type: podcast\npodcast: showa\nepisode_number: '99'\n---\nx\n")
    ContentSync.sync_file(path)
    record = Post.find_by("json_extract(metadata, '$.url_name') = ?", "uniq-a")

    get edit_admin_post_path(record)

    assert_response :success
    assert_not_includes response.body, "Already used by"
  end

  # `release` and `track_number` were defined in Post::POST_TYPES but missing
  # from the editor's known-fields hash, so the JS auto-add never surfaced them
  # and an author had to add them as custom fields. `release` renders through
  # the shared autocomplete controller: suggests music.yml keys, accepts new ones.
  test "a music post's release and track_number fields render, with release autocompleting" do
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "edit-music.md")
    File.write(path, "---\ntitle: \"Track\"\nstatus: draft\nurl_name: edit-music\n" \
                     "post_type: music\nrelease: unconfigured-release\n---\nBody.\n")
    record = Post.create!(
      file_path: path,
      content: "Body.",
      metadata: { "title" => "Track", "status" => "draft", "url_name" => "edit-music",
                  "post_type" => "music", "release" => "unconfigured-release" }
    )

    get edit_admin_post_path(record)

    assert_response :success
    # A row renders server-side only for metadata the file already has; the
    # controller adds the rest of the type's fields on load, driven by this
    # payload — which is exactly what was missing before.
    assert_includes response.body, "track_number"
    assert_select "select[data-metadata-field=?]", "release" do
      # `release` is a select built from music.yml, but a key the config
      # doesn't know still has to be selectable — otherwise opening this post
      # and saving would quietly reassign the track.
      assert_select "option[value=?][selected]", "unconfigured-release"
    end
  end

  test "edit view renders the primary actions anchor and the drawer" do
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "edit-render.md")
    File.write(path, "---\ntitle: \"Edit Render\"\nstatus: draft\nurl_name: edit-render\n---\nBody.\n")
    record = Post.create!(
      file_path: path,
      content: "Body.",
      metadata: { "title" => "Edit Render", "status" => "draft", "url_name" => "edit-render" }
    )

    get edit_admin_post_path(record)

    assert_response :success
    assert_includes response.body, 'id="primary-actions"'
    assert_includes response.body, 'data-controller="editor-drawer"'
    assert_includes response.body, 'data-editor-target="leaveModal"'
    # Indicator + publish container appear twice (top row + drawer).
    assert_equal 2, response.body.scan('data-editor-target="saveDot"').size
    assert_equal 2, response.body.scan("publish-button-container").size
  end
end
