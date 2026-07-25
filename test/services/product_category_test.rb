require "test_helper"
require "tmpdir"

class ProductCategoryTest < ActiveSupport::TestCase
  def rewrite(yaml, categories)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "store.yml")
      File.write(path, yaml)
      ProductCategory.rewritten_store_yaml_with_categories(path, categories)
    end
  end

  # The regression: a column-0 (unindented) product_categories block is valid
  # YAML, but the rewriter used to leave it behind while emitting a new indented
  # block — two lists, an unparseable file. Must replace cleanly now.
  test "replaces a column-0 product_categories block without leaving a stale list" do
    yaml = <<~YAML
      enabled: true
      product_categories:
      - album
      - book
      product_button_template: |
        hello
    YAML

    result = rewrite(yaml, %w[album apparel book])
    parsed = YAML.safe_load(result)

    assert_equal %w[album apparel book], parsed["product_categories"]
    assert_equal true, parsed["enabled"]
    assert_includes result, "hello", "unrelated keys are preserved"
  end

  test "replaces an indented product_categories block" do
    yaml = <<~YAML
      product_categories:
        - "album"
        - "book"
      currency: usd
    YAML

    parsed = YAML.safe_load(rewrite(yaml, %w[album book gear]))
    assert_equal %w[album book gear], parsed["product_categories"]
    assert_equal "usd", parsed["currency"]
  end

  test "replaces an inline array form" do
    parsed = YAML.safe_load(rewrite("product_categories: [album, book]\ncurrency: usd\n", %w[album book gear]))
    assert_equal %w[album book gear], parsed["product_categories"]
    assert_equal "usd", parsed["currency"]
  end

  test "appends when product_categories is absent" do
    parsed = YAML.safe_load(rewrite("currency: usd\n", %w[album]))
    assert_equal %w[album], parsed["product_categories"]
    assert_equal "usd", parsed["currency"]
  end
end
