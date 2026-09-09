require "test_helper"

# The metadata-ref mechanism the File/Feed importers use to list and roll back
# exactly what they created (posts + pages), keeping published content.
class ImportRefContentTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def writer
    @writer ||= ContentWriter.new
  end

  def make(kind, name, status, ref)
    meta = { "title" => name, "status" => status, "date" => "2024-01-01", "import_ref" => ref }
    meta["post_type"] = "article" if kind == :post
    slug = writer.write(kind: kind, filename: name, metadata: meta, body: "body")
    dir = (kind == :post ? RoeSitePaths::SITE_POSTS_PATH : RoeSitePaths::SITE_PAGES_PATH)
    @created << File.join(dir, "#{slug}.md")
    slug
  end

  test "counts and deletes only an import's draft content, keeping published" do
    import = Import.create!(source_type: "files", phase: 1, status: :completed)
    other  = Import.create!(source_type: "files", phase: 1, status: :completed)

    make(:post, "ref-draft-a", "draft", import.id)
    make(:page, "ref-draft-b", "draft", import.id)
    make(:post, "ref-published", "published", import.id)
    make(:post, "ref-other", "draft", other.id) # different import, must be untouched

    assert_equal 2, import.ref_draft_count, "integer import_ref matches through json_extract"
    assert_equal 1, import.ref_published_count

    deleted = import.delete_draft_content!
    assert_equal 2, deleted
    assert_not File.exist?(File.join(RoeSitePaths::SITE_POSTS_PATH, "ref-draft-a.md"))
    assert File.exist?(File.join(RoeSitePaths::SITE_POSTS_PATH, "ref-published.md")), "published kept"
    assert File.exist?(File.join(RoeSitePaths::SITE_POSTS_PATH, "ref-other.md")), "other import untouched"

    assert_equal 0, import.ref_draft_count
    assert_equal 1, import.ref_published_count
    assert_equal 1, other.ref_draft_count
  end
end
