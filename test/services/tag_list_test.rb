require "test_helper"

class TagListTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_post(name, tags)
    meta = { "title" => name, "url_name" => name, "status" => "draft",
             "post_type" => "article", "date" => "2024-01-01", "tags" => tags }
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "body")
    path = File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    @created << path
    Post.find_by(file_path: RoeSitePaths.normalize(path)) ||
      Post.find_by("json_extract(metadata, '$.url_name') = ?", slug)
  end

  def write_tags(post, tags)
    path = post.file_path
    File.write(path, FrontMatterTags.replace(File.read(path), tags))
    ContentSync.sync_file(path)
  end

  def tags_yml = File.read(TagList.file)

  # ── content.yml ───────────────────────────────────────────────────────────

  test "with_list replaces the block in place and keeps the rest of the file" do
    text = "soft_line_breaks: true\ntags:\n  - old\nsearch:\n  all_pages: false\n"
    result = TagList.with_list(text, %w[a b])

    assert_equal "soft_line_breaks: true\ntags:\n  - a\n  - b\nsearch:\n  all_pages: false\n", result
  end

  test "with_list appends a block, and writes an empty list as []" do
    assert_equal "a: 1\ntags:\n  - x\n", TagList.with_list("a: 1", %w[x])
    assert_equal "a: 1\ntags: []\n", TagList.with_list("a: 1\ntags:\n- x\n", [])
  end

  test "a list left in content.yml moves to tags.yml and out of content.yml" do
    File.write(SiteConfig::CONTENT_FILE, "soft_line_breaks: true\ntags:\n  - lab\n  - arts\nsearch:\n  all_pages: false\n")
    File.write(TagList.file, "tags:\n  - kept\n")

    assert_equal %w[arts kept lab], TagList.names.sort
    assert_equal "soft_line_breaks: true\nsearch:\n  all_pages: false\n", File.read(SiteConfig::CONTENT_FILE)
  end

  test "the list is written to tags.yml, not content.yml" do
    File.write(SiteConfig::CONTENT_FILE, "soft_line_breaks: true\n")
    make_post("tl-file", %w[tl-file-tag])

    assert_includes tags_yml, "tl-file-tag"
    assert_equal "soft_line_breaks: true\n", File.read(SiteConfig::CONTENT_FILE)
  end

  # ── Following the content ────────────────────────────────────────────────

  test "a tag joins the list the first time it's used" do
    make_post("tl-first", %w[tl-alpha])

    assert_includes TagList.names, "tl-alpha"
  end

  test "a tag leaves the list when its last use goes, not before" do
    a = make_post("tl-a", %w[tl-shared tl-only-a])
    b = make_post("tl-b", %w[tl-shared])

    write_tags(a, [])
    assert_not_includes TagList.names, "tl-only-a"
    assert_includes TagList.names, "tl-shared", "still on tl-b"

    b.destroy
    assert_not_includes TagList.names, "tl-shared"
  end

  test "a tag added in the manager stays while unused" do
    TagList.add!("tl-unused")
    post = make_post("tl-other", %w[tl-x])
    write_tags(post, [])

    assert_includes TagList.names, "tl-unused"
  end

  test "reconcile adds used tags a list is missing and removes nothing" do
    make_post("tl-rec", %w[tl-rec-tag])
    File.write(TagList.file, "tags:\n  - tl-kept\n")

    TagList.reconcile!
    assert_includes TagList.names, "tl-rec-tag"
    assert_includes TagList.names, "tl-kept"
  end

  test "the list is alphabetical, one tag per line" do
    make_post("tl-order", %w[zeta Alpha beta])

    block = tags_yml[/^tags:\n(?:  - .*\n)+/]
    names = block.lines.drop(1).map { |l| l.sub("  - ", "").strip }
    assert_equal names.sort_by(&:downcase), names
  end

  # ── Changing content ─────────────────────────────────────────────────────

  test "rename changes every file and the list" do
    a = make_post("tl-ren-a", %w[tl-musi keep])
    b = make_post("tl-ren-b", %w[tl-musi])

    assert_equal 2, TagList.rename!("tl-musi", "tl-music")
    assert_equal %w[keep tl-music], a.reload.tags
    assert_equal %w[tl-music], b.reload.tags
    assert_includes TagList.names, "tl-music"
    assert_not_includes TagList.names, "tl-musi"
  end

  test "renaming onto an existing tag merges, keeping one of each" do
    a = make_post("tl-merge-a", %w[tl-lab tl-lab-noimage])
    make_post("tl-merge-b", %w[tl-lab])

    TagList.rename!("tl-lab-noimage", "tl-lab")
    assert_equal %w[tl-lab], a.reload.tags
    assert_equal 2, TagList.usage["tl-lab"][:posts]
    assert_not TagList.usage.key?("tl-lab-noimage")
  end

  test "delete removes the tag from files and the list; the items stay" do
    a = make_post("tl-del", %w[tl-gone tl-stays])

    assert_equal 1, TagList.delete!("tl-gone")
    assert_equal %w[tl-stays], a.reload.tags
    assert_not_includes TagList.names, "tl-gone"
    assert File.exist?(a.file_path)
  end

  test "deleting an unused tag only changes the list" do
    TagList.add!("tl-solo")
    assert_equal 0, TagList.delete!("tl-solo")
    assert_not_includes TagList.names, "tl-solo"
  end

  test "add refuses blanks, commas and duplicates" do
    assert_raises(TagList::Error) { TagList.add!("  ") }
    assert_raises(TagList::Error) { TagList.add!("a, b") }
    TagList.add!("tl-dup")
    assert_raises(TagList::Error) { TagList.add!("tl-dup") }
  end

  test "spellings that differ in case stay separate tags, most used first in the dropdown" do
    make_post("tl-case-a", %w[TlCase])
    make_post("tl-case-b", %w[tlcase])
    make_post("tl-case-c", %w[tlcase])

    assert_equal 1, TagList.usage["TlCase"][:posts]
    assert_equal 2, TagList.usage["tlcase"][:posts]
    names = TagList.field_options.map { |o| o[:name] }
    assert_equal %w[tlcase TlCase], names.select { |n| n.casecmp?("tlcase") }
  end

  test "Roe's own docs are never tracked" do
    root = Documentation.normalized_documentation_path
    assert_not TagList.tracked?(Documentation.new(file_path: File.join(root, "roe", "x.md")))
    assert TagList.tracked?(Documentation.new(file_path: File.join(root, "mine.md")))
  end
end
