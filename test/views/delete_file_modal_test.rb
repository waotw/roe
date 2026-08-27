# frozen_string_literal: true

require "test_helper"

# The modal used to fall through to admin_page_path for any resource_type it
# didn't recognise. A caller that forgot delete_path got a confirm dialog wired
# to delete a *page* — a plausible-looking wrong answer on a button whose whole
# job is destroying something.
class DeleteFileModalTest < ActionView::TestCase
  def render_modal(**locals)
    render partial: "shared/delete_file_modal", locals: locals
  end

  def a_post(slug)
    Post.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{slug}.md"),
      content: "x", metadata: { "title" => slug, "url_name" => slug, "status" => "draft" })
  end

  def a_member(email)
    Member.create!(email: email, name: "DFM", tier: :free, status: :active)
  end

  test "the three known types resolve on their own" do
    post = a_post("dfm")

    render_modal(resource: post, resource_type: "post")

    assert_match admin_post_path(post), rendered
    assert_match 'id="delete-modal-post"', rendered
  end

  # This is the one that matters: no silent page-delete.
  test "an unknown type refuses instead of guessing a path" do
    page = Page.create!(file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "dfm.md"),
      content: "x", metadata: { "title" => "DFM", "url_name" => "dfm-page", "status" => "draft" })

    error = assert_raises(ActionView::Template::Error) do
      render_modal(resource: page, resource_type: "member")
    end

    assert_match(/no delete path for resource_type "member"/, error.message)
    assert_match(/pass delete_path/, error.message, "the message should say how to fix it")
  end

  test "an unknown type is fine when the caller passes a path" do
    member = a_member("dfm@example.com")

    render_modal(resource: member, resource_type: "member",
                 delete_path: admin_member_path(member))

    assert_match admin_member_path(member), rendered
    assert_match 'id="delete-modal-member"', rendered
  end

  test "the confirm label can say what actually happens" do
    member = a_member("dfm2@example.com")

    render_modal(resource: member, resource_type: "member",
                 delete_path: admin_member_path(member), confirm_label: "DELETE MEMBER")

    assert_match "DELETE MEMBER", rendered
    assert_no_match "DELETE PERMANENTLY", rendered
  end

  test "it defaults to DELETE PERMANENTLY" do
    render_modal(resource: a_post("dfm3"), resource_type: "post")

    assert_match "DELETE PERMANENTLY", rendered
  end
end
