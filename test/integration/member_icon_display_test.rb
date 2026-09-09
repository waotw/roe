# frozen_string_literal: true

require "test_helper"

# The account icon in the site header used to appear only once someone was
# signed in, which leaves a members site with no visible way in — a reader who
# already has an account has to know the sign-in URL. members.yml can now ask
# for it to be there for everyone.
#
# Off by default: on a site with a handful of members, a permanent sign-in
# affordance in the header is noise.
class MemberIconDisplayTest < ActionDispatch::IntegrationTest
  ICON = /class="site-action member-link"/

  setup do
    SiteFeature.stubs(:members_enabled?).returns(true)

    @post_path = File.join(RoeSitePaths::SITE_PATH, "posts", "zz-icon.md")
    File.write(@post_path,
      "---\ntitle: \"ZZ Icon\"\nstatus: published\nurl_name: zz-icon\ndate: 2026-01-01\n---\nBody.\n")
    @post = Post.create_or_update_from_file(@post_path)

    @pages_dir = File.join(RoeSitePaths::SITE_PATH, "pages", "members")
    FileUtils.mkdir_p(@pages_dir)
    @signin_path = nil
  end

  teardown do
    FileUtils.rm_f(@post_path)
    FileUtils.rm_f(@signin_path) if @signin_path
    Post.where(file_path: @post_path).destroy_all
    Page.where("file_path LIKE ?", "%zz-signin%").destroy_all
  end

  # The site can rename sign-in to /login, so the icon asks MemberPages rather
  # than assuming the path.
  def make_signin_page(url_name: "zz-signin")
    @signin_path = File.join(@pages_dir, "signin.md")
    File.write(@signin_path,
      "---\ntitle: \"ZZ Signin\"\nurl_name: \"#{url_name}\"\nstatus: \"published\"\n---\nSign in.\n")
    Page.create_or_update_from_file(@signin_path)
  end

  def icon_shown?
    get "/posts/zz-icon"
    assert_response :success
    response.body.match?(ICON)
  end

  test "off by default, a signed-out reader gets no icon" do
    make_signin_page

    assert_not icon_shown?, "the setting is opt-in — nothing should change for sites that never touch it"
  end

  test "on, a signed-out reader gets an icon pointing at the sign-in page" do
    make_signin_page
    SiteFeature.stubs(:always_show_member_icon?).returns(true)

    assert icon_shown?, "the whole point — a reader with an account can find their way in"
    assert_match %r{href="/zz-signin"}, response.body,
      "it must follow the page's url_name, not a hardcoded /sign-in"
  end

  # A link into a page that isn't there is worse than no link — the same rule
  # the paywall's sign-in line follows.
  test "on, but with no sign-in page, there is still no icon" do
    SiteFeature.stubs(:always_show_member_icon?).returns(true)

    assert_not icon_shown?, "an icon onto a 404 is worse than no icon"
  end

  # This is the case the setting doesn't govern: signed in, the icon has always
  # shown and still points at the account page.
  test "a signed-in member gets the account icon whatever the setting says" do
    make_signin_page
    member = Member.create!(email: "zz-icon@example.com", name: "ZZ", status: "active")
    sign_in_member(member)

    assert icon_shown?
    assert_match %r{href="/account"}, response.body
  ensure
    Member.where(email: "zz-icon@example.com").destroy_all
  end

  # Static output has no session and no working sign-in, so the signed-out icon
  # is excluded outright rather than by trusting current_member to be nil.
  test "a static render never carries the signed-out icon" do
    make_signin_page
    SiteFeature.stubs(:always_show_member_icon?).returns(true)

    assert icon_shown?, "precondition — this same page shows the icon when served"

    # Stubbed rather than assigned: CurrentAttributes are reset around every
    # request, so a value set out here never reaches the render.
    Current.stubs(:static_generation).returns(true)

    assert_not icon_shown?, "a baked file must not offer a sign-in that can't work"
  end

  # ── Reading the setting out of members.yml ──────────────────────────────

  # members.yml isn't guaranteed to be on disk — a sibling test deletes it — so
  # this writes its own and restores whatever was there, including nothing.
  def with_members_yml(body)
    path = SiteConfig::FEATURES_PATH.join("members.yml")
    original = File.exist?(path) ? File.read(path) : nil
    SiteFeature.unstub(:members_enabled?)

    File.write(path, body)
    SiteConfig.sync_from_file("features/members")
    yield
  ensure
    original ? File.write(path, original) : File.delete(path)
    SiteConfig.sync_from_file("features/members") if original
  end

  test "the setting is read from members.yml" do
    with_members_yml("display:\n  always_show_member_icon: true\n") do
      assert SiteFeature.always_show_member_icon?
    end

    with_members_yml("display:\n  always_show_member_icon: false\n") do
      assert_not SiteFeature.always_show_member_icon?
    end
  end

  # An existing members.yml has no display section at all.
  test "a members.yml written before the setting existed reads as off" do
    with_members_yml("payments:\n  enabled: false\n") do
      assert_not SiteFeature.always_show_member_icon?
    end
  end
end
