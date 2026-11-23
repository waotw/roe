require "test_helper"

# The site-wide links check: what it finds, where it says it is, and what it
# keeps. Items are written as real files and synced, as the site has them.
class LinkCheckTest < ActiveSupport::TestCase
  setup do
    @created = []
    File.delete(LinkCheck::STORE) if File.exist?(LinkCheck::STORE)
  end

  teardown do
    @created.each { |f| File.delete(f) if File.exist?(f) }
    File.delete(LinkCheck::STORE) if File.exist?(LinkCheck::STORE)
  end

  def make(kind, name, status: "published", body: "body", meta: {})
    metadata = { "title" => name.titleize, "status" => status, "date" => "2024-01-01" }.merge(meta)
    metadata["post_type"] = "article" if kind == :post
    slug = ContentWriter.new.write(kind: kind, filename: name, metadata: metadata, body: body)
    dir = kind == :post ? RoeSitePaths::SITE_POSTS_PATH : RoeSitePaths::SITE_PAGES_PATH
    path = File.join(dir, "#{slug}.md")
    @created << path
    ContentSync.sync_file(path)
    (kind == :post ? Post : Page).find_by(file_path: RoeSitePaths.normalize(path))
  end

  def media(rel)
    path = File.join(RoeSitePaths::SITE_PATH, "media", rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "x")
    @created << path
  end

  def problems_for(record, result = LinkCheck.run!)
    result["problems"].select { |p| p["item_type"] == record.class.name && p["item_id"] == record.id }
  end

  test "finds broken links, links to drafts and missing media, with where each one is" do
    media("images/lc-here.jpg")
    make(:post, "lc-draft-target", status: "draft")
    post = make(:post, "lc-source", body: <<~MD, meta: { "audio" => "/media/audio/lc-gone.mp3", "related" => [ "lc-nowhere" ] })
      Fine: ![here](/media/images/lc-here.jpg)
      Gone: ![gone](/media/images/lc-gone.jpg)
      [[posts/lc-no-such-post]] and [[posts/lc-draft-target]] and [x](/posts/lc-no-address).
    MD

    found = problems_for(post).map { |p| [ p["section"], p["type"], p["line"] || p["field"], p["target"] ] }

    assert_includes found, [ "media", "missing_media", 2, "/media/images/lc-gone.jpg" ]
    assert_includes found, [ "media", "missing_media", "audio", "/media/audio/lc-gone.mp3" ]
    assert_includes found, [ "links", "broken_internal_link", 3, "posts/lc-no-such-post" ]
    assert_includes found, [ "links", "broken_internal_link", 3, "/posts/lc-no-address" ]
    assert_includes found, [ "drafts", "draft_link", 3, "posts/lc-draft-target" ]
    assert_includes found, [ "links", "broken_internal_link", "related", "lc-nowhere" ]
    assert_equal 6, found.size, "and nothing about the image that's there"
  end

  test "a draft's own broken links are listed, marked as a draft" do
    draft = make(:page, "lc-draft-page", status: "draft", body: "[[posts/lc-missing-too]]\n")

    problem = problems_for(draft).first
    assert problem["draft"]
    assert_equal "Page", problem["item_type"]
  end

  test "counts what the dashboard shows and keeps the result in tmp/" do
    make(:post, "lc-counted", body: "[[posts/lc-not-there]]\n![x](/media/images/lc-not-there.jpg)\n")

    result = LinkCheck.run!(reason: "startup")

    assert result.dig("counts", "broken") >= 1
    assert result.dig("counts", "media") >= 1
    assert result.dig("counts", "total") >= 2
    assert_equal result, LinkCheck.latest
    assert_equal "startup", LinkCheck.latest["reason"]
    assert LinkCheck::STORE.to_s.start_with?(Rails.root.join("tmp").to_s)
  end

  test "Roe's own docs aren't part of the site's check" do
    result = LinkCheck.run!
    roe_ids = Documentation.where("file_path LIKE ?", "%/documentation/roe/%").pluck(:id)
    assert_empty result["problems"].select { |p| p["item_type"] == "Documentation" && roe_ids.include?(p["item_id"]) }
  end

  test "the header's menu names are checked, and the problem opens the layout editor on its line" do
    path = LayoutFiles.path("header")
    before = File.exist?(path) ? File.read(path) : nil
    File.write(path, "[Site](/)\n\n```collection\ntemplate: menu\norder: lc-no-such-page\n```\n")

    problem = LinkCheck.run!["problems"].find { |p| p["item_type"] == "Layout" }

    assert_equal [ "header", 5, "lc-no-such-page", "links" ], problem.values_at("item_id", "line", "target", "section")
    assert_equal "/admin/layout/header/edit?highlight=lc-no-such-page&line=5",
                 ApplicationController.helpers.link_problem_path(problem, {})
  ensure
    before ? File.write(path, before) : File.delete(path)
  end

  test "nothing stored yet reads as nil" do
    assert_nil LinkCheck.latest
  end

  test "the file watcher asks for a check when content or media changes, not for variants or config" do
    site = RoeSitePaths::SITE_PATH.to_s
    assert ContentWatcher.link_check_file?(File.join(site, "posts", "a.md"))
    assert ContentWatcher.link_check_file?(File.join(site, "media", "images", "a.jpg"))
    refute ContentWatcher.link_check_file?(File.join(site, "media", "images", "variants", "a-small.webp"))
    assert ContentWatcher.link_check_file?(File.join(site, "layout", "header.md"))
    refute ContentWatcher.link_check_file?(File.join(site, "system", "global", "site.yml"))
    refute ContentWatcher.link_check_file?(File.join(site, "theme", "default.css"))
  end

  test "roe links prints the site and Roe's docs and fails when something is broken" do
    make(:post, "lc-cli", body: "[[posts/lc-cli-missing]]\n")
    out = StringIO.new

    status = LinkCheck.cli(out)

    assert_equal 1, status
    assert_includes out.string, "SITE"
    assert_includes out.string, "ROE DOCS"
    assert_includes out.string, "Lc Cli (post) · line 1"
  end
end
