# frozen_string_literal: true

require "test_helper"

# The editor actions row is a shared partial rendered twice — in-flow at the top
# and inside the sticky bottom drawer. Lock that the edit view + partial render.
class Admin::PostsEditRenderTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    File.delete(File.join(RoeSitePaths::SITE_PATH, "posts", "edit-render.md")) rescue nil
    File.delete(File.join(RoeSitePaths::SITE_PATH, "posts", "edit-music.md")) rescue nil
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
    assert_includes response.body, 'data-metadata-field="release"'
    assert_includes response.body, 'data-autocomplete-target="input"'
    # A release absent from music.yml survives — the field is not a select.
    assert_includes response.body, "unconfigured-release"
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
