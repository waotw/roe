require "test_helper"
require "tmpdir"

# StoreConfigList surgically replaces a list key in store.yml, leaving the rest
# of the file untouched. These exercise the pure rewriter (given a path) and the
# YAML block builder — the risky part — without needing a real site store.yml.
class StoreConfigListTest < ActiveSupport::TestCase
  def with_store(contents)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "store.yml")
      File.write(path, contents)
      yield path
    end
  end

  test "replaces an existing block-style key and leaves other keys byte-identical" do
    with_store(<<~YAML) do |path|
      currency: usd
      product_groups:
        - "alpha"
      default_domain: example.com
    YAML
      out = StoreConfigList.rewritten(path, "product_groups", [ "alpha", "beta" ])
      assert_includes out, %(  - "beta")
      assert_includes out, "currency: usd"
      assert_includes out, "default_domain: example.com"
    end
  end

  test "replaces an inline array form with a block" do
    with_store("product_groups: [alpha]\ncurrency: usd\n") do |path|
      out = StoreConfigList.rewritten(path, "product_groups", [ "alpha", "beta" ])
      assert_includes out, "product_groups:\n  - \"alpha\"\n  - \"beta\""
      assert_includes out, "currency: usd"
    end
  end

  test "appends the key when it does not exist yet" do
    with_store("currency: usd\n") do |path|
      out = StoreConfigList.rewritten(path, "product_groups", [ "alpha" ])
      assert_includes out, "currency: usd"
      assert_includes out, %(product_groups:\n  - "alpha")
    end
  end

  test "empty list renders an inline []" do
    assert_equal "product_groups: []\n", StoreConfigList.yaml_block("product_groups", [])
  end

  test "quotes values so spaces survive a reparse" do
    block = StoreConfigList.yaml_block("product_groups", [ "Summer Collection" ])
    assert_includes block, %(  - "Summer Collection")
    assert_equal [ "Summer Collection" ], YAML.safe_load(block)["product_groups"]
  end
end
