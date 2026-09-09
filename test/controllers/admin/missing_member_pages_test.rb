# frozen_string_literal: true

require "test_helper"

# A user turned on the member icon and it never appeared. The sign-in page had
# been recreated in the admin, so it lived at sign-in.md instead of the
# signin.md Roe looks for — and nothing anywhere said so. The icon just didn't
# show.
#
# Roe now resolves three ways before giving up, so reaching the warning means
# the page is genuinely gone rather than renamed.
class Admin::MissingMemberPagesTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    SiteFeature.stubs(:members_enabled?).returns(true)

    @path = File.join(RoeSitePaths::SITE_PATH, "pages", "zz-mmp-lab.md")
    File.write(@path, "---\ntitle: \"ZZ Lab\"\nurl_name: \"zz-mmp-lab\"\nstatus: \"published\"\n---\n\n```form\nfor: signin\n```\n")
    @incidental = Page.create_or_update_from_file(@path)
  end

  teardown do
    FileUtils.rm_f(@path)
    Page.where(file_path: @path).destroy_all
  end

  test "a healthy site says nothing" do
    MemberPages.stubs(:missing).returns([])
    MemberPages.stubs(:guessed).returns({})

    get admin_pages_path

    assert_response :success
    assert_select "form[action=?]", restore_member_pages_admin_pages_path, 0
  end

  test "a missing sign-in page is named, with what it costs" do
    MemberPages.stubs(:missing).returns([ "signin" ])
    MemberPages.stubs(:guessed).returns({})

    get admin_pages_path

    assert_select "[data-member-pages='missing']", 1
    assert_match "sign in", response.body, "the warning should name which page"
    assert_select "form[action=?]", restore_member_pages_admin_pages_path, 1
  end

  # The warning has to appear even when there are no member pages at all —
  # that's precisely the state it exists for, and the Member Pages section is
  # hidden then.
  test "it shows even when the member pages section is hidden" do
    MemberPages.stubs(:missing).returns([ "signin", "signup" ])
    MemberPages.stubs(:guessed).returns({})

    get admin_pages_path

    assert_select "form[action=?]", restore_member_pages_admin_pages_path, 1
  end

  # Renaming is supported and shouldn't be reported as breakage — resolution
  # finds the page, so `missing` is empty and nothing is shown.
  test "a renamed page that still resolves produces no warning" do
    MemberPages.stubs(:missing).returns([])
    MemberPages.stubs(:guessed).returns({})

    get admin_pages_path

    assert_select "form[action=?]", restore_member_pages_admin_pages_path, 0,
      "warned about pages that resolve fine — the fix would be to rename them back"
  end

  # The state after deleting a sign-in page on a site where some other page
  # happens to carry the form: nothing is broken, the icon still works, but the
  # link now points somewhere incidental and the dedicated page is gone.
  test "a guessed page is named, with where Roe landed" do
    MemberPages.stubs(:missing).returns([])
    MemberPages.stubs(:guessed).returns({ "signin" => @incidental })

    get admin_pages_path

    assert_select "[data-member-pages='guessed']", 1
    assert_match @incidental.url_name, response.body, "it should say which page Roe settled on"
    assert_select "form[action=?]", restore_member_pages_admin_pages_path, 1
  end

  test "guessing and missing can be reported together" do
    MemberPages.stubs(:missing).returns([ "upgrade" ])
    MemberPages.stubs(:guessed).returns({ "signin" => @incidental })

    get admin_pages_path

    assert_select "[data-member-pages='missing']", 1
    assert_select "[data-member-pages='guessed']", 1
  end

  # A general stub first: other things install templates during a request
  # (ConfigGenerator seeds postmark), and a bare expectation catches those too.
  def stub_loader(members_result)
    SiteTemplates::Loader.stubs(:install).returns({ installed: [] })
    SiteTemplates::Loader.stubs(:install)
                         .with(folder: "features/members", destination: RoeSitePaths::SITE_PATH)
                         .returns(members_result)
  end

  test "restoring reports what it put back" do
    MemberPages.stubs(:missing).returns([ "signin" ])
    MemberPages.stubs(:guessed).returns({})
    stub_loader({ installed: [ "pages/members/signin.md" ] })
    ContentSync.stubs(:sync_all)

    post restore_member_pages_admin_pages_path

    assert_redirected_to admin_pages_path
    assert_match(/Restored 1 member file/, flash[:notice])
  end

  # The loader is skip-if-exists, so a restore that writes nothing means the
  # pages are there under names Roe can't resolve — telling someone to add
  # page_type is more use than claiming success.
  test "restoring nothing says so rather than claiming success" do
    MemberPages.stubs(:missing).returns([ "signin" ])
    MemberPages.stubs(:guessed).returns({})
    stub_loader({ installed: [] })
    ContentSync.stubs(:sync_all)

    post restore_member_pages_admin_pages_path

    assert_match(/page_type/, flash[:alert])
  end

  # The bug this covers: a site working through an incidental form has nothing
  # "missing", so the button under the warning reported nothing to do while the
  # warning stayed up.
  test "restoring acts on a guessed page, not just a missing one" do
    MemberPages.stubs(:missing).returns([])
    MemberPages.stubs(:guessed).returns({ "signin" => @incidental })
    stub_loader({ installed: [ "pages/members/signin.md" ] })
    ContentSync.stubs(:sync_all)

    post restore_member_pages_admin_pages_path

    assert_match(/Restored 1 member file/, flash[:notice])
  end

  test "restoring with nothing missing or guessed does nothing" do
    MemberPages.stubs(:missing).returns([])
    MemberPages.stubs(:guessed).returns({})

    post restore_member_pages_admin_pages_path

    assert_match(/Nothing to restore/, flash[:notice])
  end
end
