# frozen_string_literal: true

require "test_helper"

# A published post whose url_name changes can write a 301 as part of the save,
# when the editor's pre-save slug-change modal set create_redirect_from (the
# "Create redirect & save" choice). RedirectManager's own logic is covered in
# redirect_manager_test; here we prove the save path honors the stashed field.
class PostsControllerRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user)
    @post  = create(:post, metadata: {
      "title" => "Redirect Post", "status" => "published",
      "date" => "2024-01-01", "url_name" => "old-slug"
    })
    FileUtils.mkdir_p(File.dirname(@post.file_path))
    File.write(@post.file_path,
      "---\ntitle: Redirect Post\nstatus: published\ndate: 2024-01-01\nurl_name: old-slug\n---\nBody.\n")

    @path = RedirectManager::CONFIG_PATH
    @original = File.exist?(@path) ? File.read(@path) : nil
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "redirects: {}\n")
    SiteRedirectsMiddleware.reload!
  end

  teardown do
    @original ? File.write(@path, @original) : FileUtils.rm_f(@path)
    SiteRedirectsMiddleware.reload!
    FileUtils.rm_f(@post.file_path)
  end

  # Renamed metadata YAML (new slug) for the update call.
  def renamed_metadata(slug)
    "title: Redirect Post\nstatus: published\ndate: 2024-01-01\nurl_name: #{slug}\n"
  end

  test "writes the 301 when create_redirect_from is set on save" do
    sign_in_as(@admin)

    patch admin_post_path(@post), params: {
      metadata: renamed_metadata("new-slug"),
      content: "Body.",
      create_redirect_from: "/posts/old-slug"
    }

    assert_redirected_to edit_admin_post_path(@post)
    assert_equal "/posts/new-slug", RedirectManager.rules["/posts/old-slug"]["to"]
  end

  test "reverting url_name to blank redirects to the title-derived slug" do
    sign_in_as(@admin)

    # url_name blanked → effective slug falls back to the parameterized title.
    patch admin_post_path(@post), params: {
      metadata: "title: Redirect Post\nstatus: published\ndate: 2024-01-01\nurl_name: \n",
      content: "Body.",
      create_redirect_from: "/posts/old-slug"
    }

    assert_equal "/posts/redirect-post", RedirectManager.rules["/posts/old-slug"]["to"]
  end

  test "writes no redirect when create_redirect_from is absent (Keep old URL / no change)" do
    sign_in_as(@admin)

    patch admin_post_path(@post), params: {
      metadata: renamed_metadata("new-slug"),
      content: "Body."
      # no create_redirect_from — the user chose Keep old URL, or didn't rename
    }

    assert_redirected_to edit_admin_post_path(@post)
    assert_empty RedirectManager.rules
  end

  test "writes no redirect for a draft even if the field is somehow set" do
    @post.metadata["status"] = "draft"
    sign_in_as(@admin)

    patch admin_post_path(@post), params: {
      metadata: "title: Redirect Post\nstatus: draft\ndate: 2024-01-01\nurl_name: new-slug\n",
      content: "Body.",
      create_redirect_from: "/posts/old-slug"
    }

    assert_empty RedirectManager.rules
  end
end
