# frozen_string_literal: true

require "test_helper"

# Roe ships 85 docs a site may not want to publish. What happens to them used
# to be one boolean called "include in search" that actually decided whether
# they were in the database at all — so turning it off 404'd every
# /documentation/roe/… URL, including the admin's own help links.
#
# It's one dial now because the three outcomes are nested: search on the live
# site needs the files to be on the live site. Independent switches could be
# set to a state that can't exist.
class RoeDocsModeTest < ActiveSupport::TestCase
  def set(mode) = SiteConfig.stubs(:content).with("docs.roe").returns(mode)

  test "the default keeps Roe's docs off the site entirely" do
    SiteConfig.stubs(:content).returns(nil)

    assert_equal "local", Documentation.roe_docs_mode
    assert_not Documentation.roe_docs_published?
    assert_not Documentation.roe_docs_searchable?
  end

  test "published means synced and built, but not findable" do
    set("published")

    assert Documentation.roe_docs_published?
    assert_not Documentation.roe_docs_searchable?
  end

  test "searchable means all three" do
    set("searchable")

    assert Documentation.roe_docs_published?
    assert Documentation.roe_docs_searchable?
  end

  test "nonsense falls back to the default rather than half-publishing" do
    set("yes please")
    # An unrecognised value falls through to the legacy key, so that has to be
    # stubbed too or the lookup is simply unstubbed rather than defaulting.
    SiteConfig.stubs(:content).with("search.roe_docs").returns(nil)

    assert_equal "local", Documentation.roe_docs_mode
  end

  # The old boolean meant "search and static build", which is the top setting.
  test "the old search.roe_docs setting still means searchable" do
    SiteConfig.stubs(:content).with("docs.roe").returns(nil)
    SiteConfig.stubs(:content).with("search.roe_docs").returns(true)

    assert_equal "searchable", Documentation.roe_docs_mode
  end

  test "the old setting turned off still means local" do
    SiteConfig.stubs(:content).with("docs.roe").returns(nil)
    SiteConfig.stubs(:content).with("search.roe_docs").returns(false)

    assert_equal "local", Documentation.roe_docs_mode
  end

  # ── Site Sync ────────────────────────────────────────────────────────────

  test "local-only keeps Roe's docs off the wire" do
    set("local")
    SiteSync::Ledger.reset_roe_docs_cache!

    assert SiteSync::Ledger.excluded?("documentation/roe/guide.md")
    assert_not SiteSync::Ledger.excluded?("documentation/mine.md"),
      "a site's own documentation is always synced"
  ensure
    SiteSync::Ledger.reset_roe_docs_cache!
  end

  test "publishing puts them back on the wire" do
    set("published")
    SiteSync::Ledger.reset_roe_docs_cache!

    assert_not SiteSync::Ledger.excluded?("documentation/roe/guide.md")
  ensure
    SiteSync::Ledger.reset_roe_docs_cache!
  end

  # ── The database is a local index, not a publishing decision ─────────────

  # ContentSync used to skip and then delete these rows, which is what made the
  # pages 404. Whether the files reach live is Site Sync's business now.
  test "ContentSync no longer purges Roe docs" do
    source = File.read(Rails.root.join("app", "services", "content_sync.rb"))

    assert_no_match(/purge_roe_documentation/, source)
    assert_no_match(/include_roe_docs\?/, source)
  end

  test "nothing still asks the old question" do
    %w[app/services/static_generator.rb app/services/search_index_generator.rb
       app/models/documentation.rb].each do |file|
      assert_no_match(/include_roe_docs\?/, File.read(Rails.root.join(file)), file)
    end
  end
end
