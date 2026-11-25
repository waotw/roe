# frozen_string_literal: true

require "test_helper"

# Pages and products get the same rename redirect as posts: when the editor's
# slug-change modal sends create_redirect_from, the save writes a 301 from the
# old public address to the new one (RenameRedirect). The old address comes
# from the record as it was before the save, not from the browser.
class RenameRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user)
    @path = RedirectManager::CONFIG_PATH
    @original = File.exist?(@path) ? File.read(@path) : nil
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "redirects: {}\n")
    SiteRedirectsMiddleware.reload!
    @files = []
  end

  teardown do
    @original ? File.write(@path, @original) : FileUtils.rm_f(@path)
    SiteRedirectsMiddleware.reload!
    @files.each { |f| FileUtils.rm_f(f) }
  end

  def page_with(url_name, status: "published")
    file = File.join(RoeSitePaths::SITE_PATH, "pages", "rename-redirect-#{url_name}.md")
    write(file, "title: About Us\nstatus: #{status}\nurl_name: #{url_name}\n")
    ContentSync.sync_file(file)
    Page.find_by!(file_path: RoeSitePaths.normalize(file))
  end

  def product_with(url_name, status: "published")
    rel = "products/rename-redirect-#{url_name}.md"
    write(File.join(RoeSitePaths::SITE_PATH, rel), "title: Poster\nstatus: #{status}\nprice: 10\nurl_name: #{url_name}\n")
    ContentSync.sync_file(File.join(RoeSitePaths::SITE_PATH, rel))
    Product.find_by!(file_path: rel)
  end

  def write(file, yaml)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, "---\n#{yaml}---\nBody.\n")
    @files << file
  end

  test "renaming a published page writes a 301 from its old address" do
    sign_in_as(@admin)
    page = page_with("about")

    patch admin_page_path(page), params: {
      metadata: "title: About Us\nstatus: published\nurl_name: about-us\n",
      content: "Body.", create_redirect_from: "/about"
    }

    assert_redirected_to edit_admin_page_path(page)
    assert_equal "/about-us", RedirectManager.rules["/about"]["to"]
    assert_equal "Redirect added: /about → /about-us.", flash[:notice],
                 "a plain save has no notice of its own, so this is the whole message"
  end

  # The editor's green dot already says "changes saved"; a notice repeating it
  # was noise. Publishing is still announced — the dot doesn't know about it.
  test "a plain save leaves no notice, publishing still announces itself" do
    sign_in_as(@admin)
    page = page_with("plain", status: "draft")

    patch admin_page_path(page), params: { metadata: "title: About Us\nstatus: draft\nurl_name: plain\n", content: "Edited." }
    assert_nil flash[:notice]

    patch admin_page_path(page), params: { metadata: "title: About Us\nstatus: published\nurl_name: plain\n", content: "Edited." }
    assert_equal "Page published", flash[:notice]
    follow_redirect! # shows it, so it doesn't carry into the next request

    product = product_with("plain-poster")
    patch admin_product_path(product), params: { metadata: "title: Poster\nstatus: published\nprice: 10\nurl_name: plain-poster\n", content: "Edited." }
    assert_nil flash[:notice]
  end

  test "renaming a published product writes a 301 under /store" do
    sign_in_as(@admin)
    product = product_with("poster")

    patch admin_product_path(product), params: {
      metadata: "title: Poster\nstatus: published\nprice: 10\nurl_name: big-poster\n",
      content: "Body.", create_redirect_from: "/store/poster"
    }

    assert_redirected_to edit_admin_product_path(product)
    assert_equal "/store/big-poster", RedirectManager.rules["/store/poster"]["to"]
  end

  test "the old address comes from the saved record, not from what the browser sent" do
    sign_in_as(@admin)
    page = page_with("about")

    patch admin_page_path(page), params: {
      metadata: "title: About Us\nstatus: published\nurl_name: about-us\n",
      content: "Body.", create_redirect_from: "/somewhere-else"
    }

    assert_equal [ "/about" ], RedirectManager.rules.keys
  end

  test "the home page is never redirected away from /" do
    sign_in_as(@admin)
    page = page_with("home")

    patch admin_page_path(page), params: {
      metadata: "title: About Us\nstatus: published\nurl_name: welcome\n",
      content: "Body.", create_redirect_from: "/"
    }

    assert_empty RedirectManager.rules
  end

  test "no redirect without the editor's yes, or for a draft" do
    sign_in_as(@admin)
    page = page_with("about")
    patch admin_page_path(page), params: {
      metadata: "title: About Us\nstatus: published\nurl_name: about-us\n", content: "Body."
    }
    assert_empty RedirectManager.rules

    draft = product_with("draft-poster", status: "draft")
    patch admin_product_path(draft), params: {
      metadata: "title: Poster\nstatus: draft\nprice: 10\nurl_name: renamed\n",
      content: "Body.", create_redirect_from: "/store/draft-poster"
    }
    assert_empty RedirectManager.rules
  end

  test "each kind of content has one address shape" do
    assert_equal "/posts/a", Post.public_url_for("a")
    assert_equal "/a", Page.public_url_for("a")
    assert_equal "/", Page.public_url_for("home")
    assert_equal "/store/a", Product.public_url_for("a")
  end

  # The site's own links follow the item, redirect or not: links written as
  # addresses get the new address, links to the file get the new file name.
  test "a new address or file name updates the site's own links to it" do
    sign_in_as(@admin)
    page = page_with("links-target")
    linker = page_with("links-linker")
    File.write(linker.file_path, "---\ntitle: Linker\nstatus: published\nurl_name: links-linker\n---\n" \
                                 "[a](/links-target) [b](/pages/rename-redirect-links-target.md)\n")
    ContentSync.sync_file(linker.file_path)

    patch admin_page_path(page), params: {
      metadata: "title: About Us\nstatus: published\nurl_name: links-moved\n", content: "Body."
    }
    assert_includes File.read(linker.file_path), "[a](/links-moved) [b](/pages/rename-redirect-links-target.md)"
    assert_equal "Updated 1 link to it.", flash[:notice]

    patch rename_admin_page_path(page), params: { new_filename: "rename-redirect-links-renamed" }
    @files << File.join(RoeSitePaths::SITE_PATH, "pages", "rename-redirect-links-renamed.md")
    assert_includes File.read(linker.file_path), "[b](/pages/rename-redirect-links-renamed.md)"
  end

  test "the editor is told when a page's url_name is another page's address" do
    sign_in_as(@admin)
    first = page_with("clash-one")
    page_with("clash-two")

    get check_unique_admin_pages_path, params: { field: "url_name", value: "clash-two", exclude: first.id }
    assert_equal({ "taken" => true, "conflict" => "About Us" }, response.parsed_body)

    get check_unique_admin_pages_path, params: { field: "url_name", value: "clash-one", exclude: first.id }
    assert_equal false, response.parsed_body["taken"], "a page doesn't clash with itself"
  end

  test "a page Roe finds by its page_type says so in the editor" do
    sign_in_as(@admin)
    page = page_with("whatever-it-is-called")
    File.write(page.file_path, File.read(page.file_path).sub("status:", "page_type: checkout-success\nstatus:"))
    ContentSync.sync_file(page.file_path)

    get edit_admin_page_path(page)
    assert_includes response.body, "finds it by the page_type <code>checkout-success</code>"

    get edit_admin_page_path(page_with("plain-page"))
    assert_not_includes response.body, "finds it by the page_type"
  end
end
