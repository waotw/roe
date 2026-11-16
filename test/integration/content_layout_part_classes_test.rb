require "test_helper"

# The classes content layout parts draw, and the page-<url_name> class they
# share a prefix with. A page named like a part (`image`, `tags`) would carry
# that part's class on its <article> and pick up the theme's rules for it, so
# Page#name_class leaves those names out — which only works while
# ContentLayout::PART_CLASS_NAMES lists every class the parts draw.
class ContentLayoutPartClassesTest < ActionDispatch::IntegrationTest
  setup { SiteConfig.stubs(:content_layouts?).returns(true) }

  def part_suffixes(html, kind)
    Nokogiri::HTML.fragment(html).css("[class]").flat_map { |el| el["class"].split }
      .filter_map { |c| c.delete_prefix("#{kind}-") if c.start_with?("#{kind}-") }
  end

  test "every page- class a part draws is in PART_CLASS_NAMES, and fields start field-" do
    explain = ContentLayout::Explain.new("page", "[body]\n")
    (ContentLayout::BUILT_PARTS + %w[location]).each do |part|
      part_suffixes(explain.send(:sample, part), "page").each do |suffix|
        next if suffix.start_with?("field-")

        assert_includes ContentLayout::PART_CLASS_NAMES, suffix, "page-#{suffix} (from [#{part}])"
      end
    end
  end

  test "a metadata field draws <kind>-field <kind>-field-<name>, never <kind>-<name>" do
    post = create(:post, metadata: { "title" => "T", "url_name" => "field-post", "status" => "published",
                                     "post_type" => "article", "header" => "Hi" }, content: "x")
    ContentLayout.stubs(:for).returns(ContentLayout.parse("article", "[header]\n[body]\n"))
    get "/posts/#{post.url_name}"
    assert_select "p.post-field.post-field-header", "Hi"
    assert_select "p.post-header", 0
  end

  test "a page named like a part gets no page-<url_name> class; others keep theirs" do
    clash = create(:page, metadata: { "title" => "Images", "url_name" => "image", "status" => "published" }, content: "x")
    fine = create(:page, metadata: { "title" => "Store", "url_name" => "store", "status" => "published" }, content: "x")
    field = create(:page, metadata: { "title" => "F", "url_name" => "field-notes", "status" => "published" }, content: "x")

    get "/#{clash.url_name}"
    assert_select "article.page"
    assert_select "article.page-image", 0
    get "/#{fine.url_name}"
    assert_select "article.page.page-store"
    get "/#{field.url_name}"
    assert_select "article.page-field-notes", 0
  end
end
