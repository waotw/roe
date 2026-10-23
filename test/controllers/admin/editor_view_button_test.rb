# frozen_string_literal: true

require "test_helper"

# VIEW sat on a line of its own under the editor's actions. It's beside
# Publish/Unpublish now, before the save-state indicator, in both copies of
# the actions: the row at the top and the bar along the bottom.
class Admin::EditorViewButtonTest < ActionDispatch::IntegrationTest
  setup { @written = []; sign_in_as(User.take) }
  teardown { @written.each { |f| File.delete(f) if File.exist?(f) } }

  def post_with(status, n)
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "vb#{n}.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"VB#{n}\"\nstatus: \"#{status}\"\n---\n\nBody.\n")
    @written << path
    Post.create!(file_path: path, content: "Body.",
                 metadata: { "title" => "VB#{n}", "url_name" => "vb#{n}", "status" => status })
  end

  def view_links = css_select("a").select { |a| a.text.strip == "View" }

  test "a published or unlisted post's View is in the primary actions, top and bottom" do
    %w[published unlisted].each_with_index do |status, i|
      get edit_admin_post_path(post_with(status, i))
      assert_response :success

      assert_equal 2, view_links.size, "#{status}: one at the top, one in the bottom bar"
      assert_select "#primary-actions a", text: "View", count: 1
      assert_select "[data-controller='editor-drawer'] a", text: "View", count: 1

      # Between Publish/Unpublish and the save-state indicator.
      row = css_select("#primary-actions > div").first.children.select(&:element?)
      names = row.map { |el| el.name == "a" ? el.text.strip : (el["class"].to_s.include?("publish-button-container") ? "publish" : el.name) }
      assert_equal names.index("publish") + 1, names.index("View"), "#{status}: #{names.inspect}"
      assert_includes row[names.index("View") + 1].to_s, "saveDot"
    end
  end

  test "a draft has no View" do
    get edit_admin_post_path(post_with("draft", 9))
    assert_response :success
    assert_empty view_links
  end
end
