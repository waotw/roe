require "test_helper"

# #status has always defaulted a missing value to "draft" while the scopes
# matched the raw JSON — so an item with no status belonged to no scope, went
# missing from every total, and was called a draft by one half of the code and
# nothing by the other.
class MissingStatusTest < ActiveSupport::TestCase
  setup do
    @dir = File.join(RoeSitePaths::SITE_PATH, "pages")
    FileUtils.mkdir_p(@dir)
    @path = File.join(@dir, "zz-no-status-test.md")
    File.write(@path, "---\ntitle: \"No Status\"\nurl_name: \"zz-no-status-test\"\n---\n\nbody\n")
    @page = Page.create_or_update_from_file(@path)
  end

  teardown do
    FileUtils.rm_f(@path)
    Page.where(file_path: RoeSitePaths.normalize(@path)).destroy_all
  end

  test "the reader still calls it a draft" do
    assert_equal "draft", @page.status
  end

  test "the drafts scope now contains it" do
    assert_includes Page.drafts.pluck(:id), @page.id,
      "#status says draft, so the scope has to agree"
  end

  test "it isn't published or unlisted" do
    assert_not_includes Page.published.pluck(:id), @page.id
    assert_not_includes Page.unlisted.pluck(:id), @page.id
    assert_not_includes Page.public_items.pluck(:id), @page.id
  end

  test "not_draft excludes it" do
    assert_not_includes Page.not_draft.pluck(:id), @page.id
  end

  # The whole point: the columns add up.
  test "the status scopes account for every record" do
    [ Post, Page ].each do |model|
      counted = model.published.count + model.unlisted.count + model.drafts.count
      assert_equal model.count, counted,
        "#{model.name}: #{model.count} records but the scopes account for #{counted}"
    end
  end

  test "an explicit status is unaffected" do
    File.write(@path, "---\ntitle: \"No Status\"\nurl_name: \"zz-no-status-test\"\nstatus: \"published\"\n---\n\nbody\n")
    page = Page.create_or_update_from_file(@path)

    assert_includes Page.published.pluck(:id), page.id
    assert_not_includes Page.drafts.pluck(:id), page.id
  end
end
