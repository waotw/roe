# frozen_string_literal: true

require "test_helper"

# Posts follow the same publish model: present title/date → read-only "✓"
# bullets, missing → inputs (date prefilled with today). Audience/distribution
# stay explicit radios (unaffected here).
class Admin::PostsPublishModalTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def teardown
    File.delete(File.join(RoeSitePaths::SITE_PATH, "posts", "pub-post.md")) rescue nil
  end

  test "present title is a ✓ bullet; missing date is a date input prefilled with today" do
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "pub-post.md")
    File.write(path, "---\ntitle: \"Hello There\"\nstatus: draft\nurl_name: pub-post\n---\nBody.\n")
    record = Post.create!(
      file_path: path,
      content: "Body.",
      metadata: { "title" => "Hello There", "status" => "draft", "url_name" => "pub-post" }
    )

    post publish_modal_admin_post_path(record),
         params: { metadata: "title: Hello There\nstatus: draft\nurl_name: pub-post\n" }

    assert_response :success
    # Present title → confirmation bullet.
    assert_includes response.body, "✓"
    assert_includes response.body, "Hello There"
    # Missing date → date input, prefilled with today.
    assert_includes response.body, 'name="metadata_fields[date]"'
    assert_includes response.body, 'type="date"'
    assert_includes response.body, Date.today.iso8601
  end
end
