# frozen_string_literal: true

require "test_helper"

# The editor actions row is a shared partial rendered twice — in-flow at the top
# and inside the sticky bottom drawer. Lock that the edit view + partial render.
class Admin::PostsEditRenderTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    File.delete(File.join(RoeSitePaths::SITE_PATH, "posts", "edit-render.md")) rescue nil
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
    # Indicator + publish container appear twice (top row + drawer).
    assert_equal 2, response.body.scan('data-editor-target="saveDot"').size
    assert_equal 2, response.body.scan("publish-button-container").size
  end
end
