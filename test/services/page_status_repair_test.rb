require "test_helper"

# A page with no status is neither published nor unlisted, so
# SiteController#check_draft_access! 404s it for anyone not signed in. On older
# installs that includes the Stripe return pages — a customer finishing a
# payment lands on a 404, and the site owner never sees it because they're
# signed in.
class PageStatusRepairTest < ActiveSupport::TestCase
  setup do
    @dir = File.join(RoeSitePaths::SITE_PATH, "pages", "members")
    FileUtils.mkdir_p(@dir)
    @path = File.join(@dir, "checkout-success.md")
    @original = File.exist?(@path) ? File.binread(@path) : nil
  end

  teardown do
    @original ? File.write(@path, @original) : FileUtils.rm_f(@path)
    FileUtils.rm_f(File.join(@dir, "my-own-page.md"))
  end

  def write_page(path, front)
    File.write(path, "---\n#{front}---\n\nbody\n")
    Page.create_or_update_from_file(path)
  end

  test "a Roe page with no status is found, with the template's value" do
    write_page(@path, %(title: "Checkout - Success"\nurl_name: "checkout-success"\n))

    pending = PageStatusRepair.pending
    match = pending.find { |r| r.path.to_s.include?("checkout-success") }

    assert match, "the page should be pending repair"
    assert_equal "published", match.status
  end

  test "repairing writes the status into the file" do
    write_page(@path, %(title: "Checkout - Success"\nurl_name: "checkout-success"\n))

    PageStatusRepair.repair!

    assert_match(/^status: "published"$/, File.read(@path))
  end

  # The rest of the front matter must survive — a repair shouldn't reformat.
  test "the rest of the file is left alone" do
    write_page(@path, %(title: "Checkout - Success"\nurl_name: "checkout-success"\nmember_page: true\ntags: []\n))

    PageStatusRepair.repair!
    content = File.read(@path)

    assert_match "member_page: true", content
    assert_match "tags: []", content
    assert_match "body", content
  end

  test "a page that already has a status is untouched" do
    write_page(@path, %(title: "Checkout - Success"\nurl_name: "checkout-success"\nstatus: "unlisted"\n))

    assert_empty PageStatusRepair.pending.select { |r| r.path.to_s.include?("checkout-success") },
      "a status the user chose is not ours to overwrite"
  end

  # The narrow scope: only pages Roe shipped a template for.
  test "a page the user wrote is never touched" do
    mine = File.join(@dir, "my-own-page.md")
    write_page(mine, %(title: "Mine"\nurl_name: "my-own-page"\n))

    assert_empty PageStatusRepair.pending.select { |r| r.path.to_s.include?("my-own-page") }
  end

  test "repairing twice changes nothing the second time" do
    write_page(@path, %(title: "Checkout - Success"\nurl_name: "checkout-success"\n))

    assert_equal 1, PageStatusRepair.repair!.count { |r| r.path.to_s.include?("checkout-success") }
    assert_empty PageStatusRepair.pending.select { |r| r.path.to_s.include?("checkout-success") }
  end
end
