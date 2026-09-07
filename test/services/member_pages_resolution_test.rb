# frozen_string_literal: true

require "test_helper"

# MemberPages resolved by filename only, so a sign-in page recreated in the
# admin — titled "Sign In", which parameterizes to sign-in.md — went invisible.
# No sign-in link anywhere, and nothing said why.
#
# A page can now declare what it's FOR, separately from what it's called.
class MemberPagesResolutionTest < ActiveSupport::TestCase
  setup do
    @dir = File.join(RoeSitePaths::SITE_PATH, "pages")
    FileUtils.mkdir_p(File.join(@dir, "members"))
    @written = []
  end

  teardown do
    @written.each { |p| FileUtils.rm_f(p) }
    Page.where("file_path LIKE ?", "%zz-mpr%").destroy_all
  end

  def make_page(relative, metadata: {}, content: "")
    path = File.join(@dir, relative)
    @written << path
    front = { "title" => "ZZ MPR", "url_name" => "zz-mpr-#{SecureRandom.hex(3)}",
              "status" => "published" }.merge(metadata)
    yaml = front.map { |k, v| "#{k}: \"#{v}\"" }.join("\n")
    File.write(path, "---\n#{yaml}\n---\n\n#{content}\n")
    Page.create_or_update_from_file(path)
  end

  # The case the user hit: renamed file, no marker, but it still renders the form.
  test "a renamed sign-in page is still found by the form it renders" do
    page = make_page("zz-mpr-sign-in.md", content: "```form\nfor: signin\n```")

    assert_equal page.file_path, MemberPages.find("signin")&.file_path
  end

  # Declared beats derived: this one wins even though another page has the form.
  test "a page that declares its type wins" do
    make_page("zz-mpr-other.md", content: "```form\nfor: signin\n```")
    declared = make_page("zz-mpr-declared.md", metadata: { "page_type" => "signin" })

    assert_equal declared.file_path, MemberPages.find("signin")&.file_path
  end

  # More than one page carries the form — an upgrade page usually does — so the
  # answer has to be stable rather than whichever row came back first.
  test "several pages with the form resolve deterministically" do
    make_page("zz-mpr-zzz.md", content: "```form\nfor: signin\n```")
    inside = make_page("members/zz-mpr-inside.md", content: "```form\nfor: signin\n```")

    3.times { assert_equal inside.file_path, MemberPages.find("signin")&.file_path }
  end

  # A dedicated page beats an incidental form. A signup page offering "already a
  # member? sign in" carries the form but isn't the sign-in page, and pointing
  # the account icon at it sends people somewhere arbitrary.
  test "a dedicated page wins over a page that merely contains the form" do
    incidental = make_page("zz-mpr-incidental.md", content: "```form\nfor: unsubscribe\n```")
    dedicated  = make_page("members/unsubscribe.md")

    resolution = MemberPages.resolve("unsubscribe")

    assert_equal dedicated.file_path, resolution.page.file_path
    assert_equal :conventional, resolution.how
    assert_not resolution.guessed?
    assert_not_equal incidental.file_path, resolution.page.file_path
  end

  # Working, but not the way Roe intends — the dedicated page is gone and the
  # link now rests on a form someone could edit away without connecting the two.
  test "resolving only by form content reports itself as a guess" do
    make_page("zz-mpr-guess.md", content: "```form\nfor: donate\n```")

    resolution = MemberPages.resolve("donate")

    assert resolution.found?
    assert resolution.guessed?, "a guess that doesn't say so is worse than no answer"
    assert_includes MemberPages.guessed.keys, "donate" if MemberPages.required_stems.include?("donate")
  end

  test "nothing anywhere means nothing found, not a guess" do
    assert_nil MemberPages.find("zz-nonexistent-stem")
  end

  # Existing installs have neither a marker nor, necessarily, a form block in
  # the page — the form may sit in a partial or the page may be a link-out. The
  # filename Roe originally shipped has to keep working untouched.
  test "the conventional filename still resolves with no marker and no form" do
    path = File.join(@dir, "members", "unsubscribe.md")
    @written << path
    File.write(path, "---\ntitle: \"ZZ MPR Unsub\"\nurl_name: \"zz-mpr-unsub\"\nstatus: \"published\"\n---\n\nNo form here.\n")
    Page.create_or_update_from_file(path)

    assert_equal path, MemberPages.find("unsubscribe")&.file_path
  end

  # The static build excludes member pages because they post to Rails endpoints
  # a baked site hasn't got. Excluding by directory alone would bake a declared
  # sign-in page that had been moved, producing a form that silently fails.
  test "a declared member page is kept out of the static build" do
    declared = make_page("zz-mpr-static.md", metadata: { "page_type" => "signin" })
    ordinary = make_page("zz-mpr-ordinary.md")

    ids = StaticGenerator.new.send(:static_pages_scope).pluck(:id)

    assert_not_includes ids, declared.id, "a form that posts nowhere would be baked into the static site"
    assert_includes ids, ordinary.id, "an ordinary page was excluded"
  end

  test "page_type marks a member page wherever the file lives" do
    page = make_page("zz-mpr-anywhere.md", metadata: { "page_type" => "signin" })

    assert page.member_page?, "a declared member page outside pages/members/ wasn't recognised"
  end
end
