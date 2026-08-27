# frozen_string_literal: true

require "test_helper"

# store.yml drifting immediately after a sync.
#
# Product has `after_save :register_category`, which appends the product's
# category to store.yml — but it decides what's already there by reading
# SiteConfig, i.e. the database, not the file. ContentSync#sync_site_config
# only syncs site.yml, so after an rsync brings a new store.yml in, the
# database still holds the pre-sync categories while the file holds the new
# ones. Every product that then syncs is judged against the stale list.
#
# Two consequences, both visible to the user:
#   the file gets rewritten, so it drifts from the ledger written moments
#   earlier; and each write starts from the same stale list, so categories
#   written by an earlier product in the same run are dropped.
class ProductCategorySyncTest < ActiveSupport::TestCase
  def store_path
    SiteConfig::FEATURES_PATH.join("store.yml")
  end

  def write_store(categories)
    FileUtils.mkdir_p(File.dirname(store_path))
    body = +"currency: usd\ndefault_domain: \"\"\n"
    body << if categories.empty?
      "product_categories: []\n"
    else
      "product_categories:\n" + categories.map { |c| "  - \"#{c}\"" }.join("\n") + "\n"
    end
    File.write(store_path, body)
  end

  def file_categories
    YAML.load_file(store_path)["product_categories"] || []
  end

  def product(category, n)
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "p#{n}.md"),
      content: "Body.",
      metadata: { "title" => "P#{n}", "url_name" => "p#{n}", "status" => "published",
                  "category" => category, "price" => "10.00" }
    )
  end

  teardown do
    File.delete(store_path) if File.exist?(store_path)
    SiteConfig.reload!("features/store")
  end

  # The state right after an rsync: the file has the peer's categories, the
  # database still has ours, because nothing re-synced features/store.
  def with_stale_database(file_categories:, database_categories:)
    write_store(database_categories)
    SiteConfig.sync_from_file("features/store")
    write_store(file_categories)
    SiteConfig.reload!("features/store")
  end

  # The invariant that makes all of the above hold: the registry reads the
  # file it writes. Reading SiteConfig instead is what let a stale database
  # decide what store.yml should contain.
  test "the registry reads the file, not the database" do
    write_store(%w[book ebook])
    SiteConfig.sync_from_file("features/store")

    write_store(%w[zine])
    SiteConfig.reload!("features/store")

    assert_equal %w[zine], ProductCategory.all,
      "the database still says book/ebook; the file is what counts"
    assert_equal %w[zine], StoreConfigList.all("product_categories")
  end

  # A missing or broken file shouldn't blank the editor's autocomplete.
  test "an unreadable file falls back to the database rather than nothing" do
    write_store(%w[book ebook])
    SiteConfig.sync_from_file("features/store")
    File.delete(store_path)

    assert_equal %w[book ebook], ProductCategory.all
  end

  test "a synced-in store.yml is rewritten from the stale database list" do
    with_stale_database(file_categories: %w[book ebook zine], database_categories: %w[old])

    assert_equal %w[book ebook zine], file_categories, "precondition"

    product("book", 1)

    assert_equal %w[book ebook zine], file_categories,
      "store.yml was rewritten from the database's stale category list"
  end

  test "categories written by an earlier product in the same run are lost" do
    with_stale_database(file_categories: [], database_categories: [])

    product("book", 1)
    product("ebook", 2)

    assert_equal %w[book ebook], file_categories,
      "each write restarts from the stale list, so the first category is dropped"
  end

  test "the file changes at all, which is what the ledger sees as drift" do
    with_stale_database(file_categories: %w[book ebook zine], database_categories: %w[old])
    before = File.read(store_path)

    product("book", 1)

    assert_equal before, File.read(store_path),
      "store.yml changed after a sync, so the drift banner lights up"
  end
end
