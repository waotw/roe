require "test_helper"

# A count tells you how bad it is; a link tells you what to do about it. An
# "Inactive recipient" needs their address fixed or their account disabled, and
# neither is possible from a number.
class NewsletterFailureLinksTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)

    # The editor reads the file off disk, and Post stores an absolute path —
    # the factory's relative one raises ENOENT before the view is reached.
    @path = File.join(RoeSitePaths::SITE_PATH, "posts", "zz-links.md")
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "---\ntitle: \"ZZ Links\"\nstatus: \"published\"\n---\n\nBody.\n")

    @post = Post.create!(
      file_path: @path,
      content: "Body.",
      metadata: { "title" => "ZZ Links", "url_name" => "zz-links",
                  "status" => "published", "date" => "2026-01-01" }
    )

    @ok     = Member.create!(email: "ok-links@example.test", name: "Fine", status: :active)
    @failed = Member.create!(email: "bad-links@example.test", name: "Broken", status: :active)

    NewsletterSend.record!(post: @post, member: @ok, message_id: "m-1")
    NewsletterSend.record!(post: @post, member: @failed, error: "Inactive recipient")

    # The panel treats a send in the last five seconds as a job still running
    # and shows a spinner instead of the result — so a fixture created now
    # never reaches the branch under test. Backdating is the fixture working
    # around that heuristic, which is exactly why it's carded for 0.4.0.
    NewsletterSend.where(post: @post).update_all(sent_at: 1.hour.ago, attempted_at: 1.hour.ago)
  end

  teardown do
    NewsletterSend.where(post: @post).delete_all
    Member.where(id: [ @ok.id, @failed.id ]).delete_all
    @post.destroy
    FileUtils.rm_f(@path)
  end

  test "a failed member links to their admin page" do
    get edit_admin_post_path(@post)

    assert_response :success
    assert_select "a[href=?]", admin_member_path(@failed), text: @failed.email
  end

  test "a delivered member isn't listed as a failure" do
    get edit_admin_post_path(@post)

    assert_select "a[href=?]", admin_member_path(@ok), count: 0
  end

  test "failures are grouped under their reason" do
    get edit_admin_post_path(@post)

    assert_match "1 \u00d7 Inactive recipient", response.body
  end

  # The list is behind a disclosure, so the panel stays one line.
  test "the failure list is collapsed" do
    get edit_admin_post_path(@post)

    assert_select "details summary", text: "Details"
  end

  # A member deleted after a failed send shouldn't take the page down.
  test "a removed member doesn't raise" do
    @failed.destroy

    get edit_admin_post_path(@post)

    assert_response :success
  end
end
