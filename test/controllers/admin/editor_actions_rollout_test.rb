# frozen_string_literal: true

require "test_helper"

# The shared editor actions bar + drawer + leave modal now render across all
# content types. Lock that each edit view renders and shows the right controls:
# pages are publishable (Publish/Unpublish + Duplicate/Delete), emails are not
# (Save + Preview only). Posts are covered by posts_edit_render_test; products
# share pages' exact code path (resource_type only differs).
class Admin::EditorActionsRolloutTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    File.delete(File.join(RoeSitePaths::SITE_PATH, "pages", "actions-page.md")) rescue nil
    File.delete(File.join(RoeSitePaths::SITE_PATH, "emails", "actions-email.md")) rescue nil
    File.delete(File.join(RoeSitePaths::SITE_PATH, "products", "actions-product.md")) rescue nil
  end

  test "product edit renders the shared actions bar, drawer, publish" do
    rel = "products/actions-product.md"
    path = File.join(RoeSitePaths::SITE_PATH, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"Actions Product\"\nstatus: draft\nprice: 10\nurl_name: actions-product\n---\nBody.\n")
    record = Product.create!(
      file_path: rel,
      content: "Body.",
      metadata: { "title" => "Actions Product", "status" => "draft", "price" => 10, "url_name" => "actions-product" }
    )

    get edit_admin_product_path(record)

    assert_response :success
    assert_includes response.body, 'id="primary-actions"'
    assert_includes response.body, 'data-controller="editor-drawer"'
    assert_includes response.body, 'data-editor-target="leaveModal"'
    assert_equal 2, response.body.scan("publish-button-container").size
  end

  test "page edit renders the shared actions bar, drawer, publish, leave modal" do
    path = File.join(RoeSitePaths::SITE_PATH, "pages", "actions-page.md")
    File.write(path, "---\ntitle: \"Actions Page\"\nstatus: draft\nurl_name: actions-page\n---\nBody.\n")
    record = Page.create!(
      file_path: path,
      content: "Body.",
      metadata: { "title" => "Actions Page", "status" => "draft", "url_name" => "actions-page" }
    )

    get edit_admin_page_path(record)

    assert_response :success
    assert_includes response.body, 'id="primary-actions"'
    assert_includes response.body, 'data-controller="editor-drawer"'
    assert_includes response.body, 'data-editor-target="leaveModal"'
    assert_equal 2, response.body.scan('data-editor-target="saveDot"').size
    assert_equal 2, response.body.scan("publish-button-container").size # top + drawer
    assert_includes response.body, "Duplicate"
  end

  test "email edit renders shared bar but no publish/duplicate (not publishable)" do
    path = File.join(RoeSitePaths::SITE_PATH, "emails", "actions-email.md")
    File.write(path, "Hello @member_name.\n")

    get edit_admin_email_path("actions-email")

    assert_response :success
    assert_includes response.body, 'id="primary-actions"'
    assert_includes response.body, 'data-controller="editor-drawer"'
    assert_includes response.body, 'data-editor-target="leaveModal"'
    assert_equal 2, response.body.scan('data-editor-target="saveDot"').size
    assert_not_includes response.body, "publish-button-container"
  end
end
