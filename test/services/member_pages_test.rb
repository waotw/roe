require "test_helper"

# Member pages are ordinary Pages whose URL comes from url_name, so a site
# owner can rename sign-in to /login at any time. Six block renderers had the
# paths written in, which meant a rename silently 404'd the paywall button and
# the signup fallback with no way to find them but grep.
class MemberPagesTest < ActiveSupport::TestCase
  setup do
    @dir = File.join(RoeSitePaths::SITE_PATH, "pages", "members")
    FileUtils.mkdir_p(@dir)
    @written = []
  end

  teardown do
    @written.each { |p| FileUtils.rm_f(p) }
    Page.where("file_path LIKE ?", "%zz-mp-%").destroy_all
  end

  def make_page(stem, url_name)
    path = File.join(@dir, "#{stem}.md")
    @written << path
    File.write(path, "---\ntitle: \"ZZ MP #{stem}\"\nurl_name: \"#{url_name}\"\nstatus: \"published\"\n---\n\nzz-mp-body\n")
    Page.create_or_update_from_file(path)
  end

  test "resolves a page's url from its url_name" do
    make_page("signin", "sign-in")

    assert_equal "/sign-in", MemberPages.url_for("signin")
  end

  # The whole point: rename the page, the links follow.
  test "a renamed page moves its url" do
    make_page("signin", "members/enter")

    assert_equal "/members/enter", MemberPages.url_for("signin")
  end

  # nil, not a guess — a link to a page that doesn't exist is worse than none.
  test "a missing page resolves to nothing" do
    assert_nil MemberPages.url_for("zz-does-not-exist")
    assert_not MemberPages.exists?("zz-does-not-exist")
  end

  # For callers that must render something.
  # The conventional paths aren't derivable from the stem — "signin" ships as
  # /sign-in, "signup" as /sign-up — so they're written out. Deriving them
  # produced /signup, a different and already-routed URL.
  test "url_for! falls back to the path Roe ships" do
    assert_equal "/sign-in", MemberPages.url_for!("signin")
    assert_equal "/sign-up", MemberPages.url_for!("signup")
    assert_equal "/upgrade", MemberPages.url_for!("upgrade")
  end

  test "url_for! prefers a real page over the fallback" do
    make_page("signin", "members/enter")

    assert_equal "/members/enter", MemberPages.url_for!("signin")
  end

  test "url_for! takes an explicit fallback" do
    assert_equal "/custom", MemberPages.url_for!("zz-nope", fallback: "/custom")
  end

  test "a page outside members/ is still found" do
    path = File.join(RoeSitePaths::SITE_PATH, "pages", "signin.md")
    @written << path
    File.write(path, "---\ntitle: \"ZZ MP root\"\nurl_name: \"login\"\nstatus: \"published\"\n---\n\nzz-mp-body\n")
    Page.create_or_update_from_file(path)

    assert_equal "/login", MemberPages.url_for("signin")
  end
end
