# frozen_string_literal: true

require "test_helper"

# The editor's Preview (button + Cmd/Ctrl+P) POSTs the current textarea content
# so the preview reflects unsaved edits, not the last-saved file. Lock that the
# preview endpoint honors posted content.
class Admin::PreviewUnsavedTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    File.delete(File.join(RoeSitePaths::SITE_PATH, "posts", "prev-test.md")) rescue nil
  end

  test "post preview renders POSTed (unsaved) content, not the saved file" do
    record = Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "prev-test.md"),
      content: "Saved body only.",
      metadata: { "title" => "Prev", "status" => "published", "url_name" => "prev-test" }
    )

    post preview_admin_post_path(record),
         params: { content: "# Unsaved Heading Here", metadata: "title: Prev\nstatus: published\nurl_name: prev-test\n" }

    assert_response :success
    assert_includes response.body, "Unsaved Heading Here"
    assert_not_includes response.body, "Saved body only."
  end
end
