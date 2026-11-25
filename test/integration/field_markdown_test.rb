require "test_helper"

# A subtitle, excerpt, product description or layout field can hold inline
# Markdown. It renders wherever the value is shown as HTML, and comes out as
# plain text wherever it's text: meta tags, feeds, the cart, the search index.
class FieldMarkdownTest < ActionDispatch::IntegrationTest
  setup { SiteConfig.stubs(:content_layouts?).returns(true) }

  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*#{ContentLayout::EXT}")).each { |f| FileUtils.rm_f(f) }
  end

  def site_layout(name, text)
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
    path = ContentLayout.site_path(name)
    File.write(path, text)
    File.utime(Time.now + rand(1..1000), Time.now + rand(1..1000), path)
  end

  def a_post(url_name = "marked", content: "Words.", **fields)
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "#{url_name}.md"),
      content: content,
      metadata: { "title" => "Marked Post", "url_name" => url_name, "status" => "published",
                  "date" => "2024-03-05", "audience" => "everyone" }.merge(fields.transform_keys(&:to_s))
    )
  end

  def a_product(**fields)
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "thing.md"),
      content: "About it.",
      metadata: { "title" => "Thing", "url_name" => "thing", "status" => "published",
                  "sku" => "THING", "price" => 12.0 }.merge(fields.transform_keys(&:to_s))
    )
  end

  def fragment(html) = Nokogiri::HTML::DocumentFragment.parse(html)

  QUOTE = "_the quote_\n— benjamin welch"

  test "a layout field renders its Markdown inside its one <p>" do
    site_layout("article", "[pullquote]\n[body]\n")
    get post_path(a_post(pullquote: QUOTE).url_name)

    assert_select "p.post-field.post-field-pullquote", 1
    assert_select "p.post-field-pullquote > em", "the quote"
    assert_select "p.post-field-pullquote > br", 1
    assert_select "p.post-field-pullquote", text: /— benjamin welch/
  end

  test "a field line starting with a dash stays text, not a list" do
    site_layout("article", "[pullquote]\n[body]\n")
    get post_path(a_post(pullquote: "_the quote_\n- benjamin welch").url_name)

    assert_select "p.post-field-pullquote", text: /- benjamin welch/
    assert_select ".post-field-pullquote li, .post-field-pullquote + ul", 0
  end

  test "subtitle and excerpt boxes render their Markdown" do
    site_layout("article", "[title]\n[subtitle]\n[excerpt]\n[body]\n")
    get post_path(a_post(subtitle: "On *Moby Dick*", excerpt: "A **bold** claim").url_name)

    assert_select "p.post-subtitle > em", "Moby Dick"
    assert_select "p.post-excerpt > strong", "bold"
  end

  test "a product's description box renders its Markdown" do
    site_layout("product", "[title] [description]\n[body]\n")
    get product_path(a_product(description: "Printed on *heavy* paper").url_name)

    assert_select "p.product-description > em", "heavy"
  end

  test "meta descriptions are plain text" do
    get post_path(a_post(excerpt: "A **bold** claim about *Moby Dick*").url_name)

    assert_select "meta[property='og:description'][content=?]", "A bold claim about Moby Dick"
  end

  test "a collection shows subtitles and excerpts with their Markdown" do
    a_post(subtitle: "On *Moby Dick*", excerpt: "A **bold** claim")
    %w[list full links compact glossary].each do |template|
      host = Post.new(content: "```collection\ntemplate: #{template}\nshow_excerpt: true\nshow_subtitle: true\n```\n",
                      metadata: { "title" => "Host", "status" => "published" })
      html = fragment(host.to_html)

      assert_equal "Moby Dick", html.at_css(".item-subtitle em")&.text, template
      assert_no_match(/\*Moby Dick\*/, html.to_html, template)
      next unless %w[full glossary].include?(template)

      assert_equal "bold", html.at_css(".item-excerpt strong")&.text, template
    end
  end

  test "a post-link card shows the subtitle and excerpt with their Markdown" do
    a_post(subtitle: "On *Moby Dick*", excerpt: "A **bold** claim")
    host = Post.new(content: "```card\ntype: post-link\npost: marked\nstyle: large\n```\n",
                    metadata: { "title" => "Host", "status" => "published" })
    html = fragment(host.to_html)

    assert_equal "Moby Dick", html.at_css(".card-subtitle em")&.text
    assert_equal "bold", html.at_css(".card-excerpt strong")&.text
  end

  test "a card excerpt too long to fit is cut as plain text, with no stray marks" do
    a_post(excerpt: "#{'word ' * 70}and *then* more")
    host = Post.new(content: "```card\ntype: post-link\npost: marked\nstyle: large\n```\n",
                    metadata: { "title" => "Host", "status" => "published" })
    excerpt = fragment(host.to_html).at_css(".card-excerpt").text

    assert excerpt.end_with?("...")
    assert_not_includes excerpt, "*"
  end

  test "feeds, the cart line and the search index get plain text" do
    post = a_post(excerpt: "A **bold** claim", subtitle: "On *Moby Dick*")
    product = a_product(description: "Printed on *heavy* paper", variant: "Paperback")

    rss = FeedGenerator.new(posts: Post.where(id: post.id), format: :rss,
                            site_config: { title: "T", url: "https://example.com", description: "D", author: "A" }).generate
    item = Nokogiri::XML(rss).at_xpath("//item/description").text
    assert_equal "A bold claim", item

    assert_equal "Paperback — Printed on heavy paper", product.snipcart_description

    entry = SearchIndexGenerator.build[:entries].find { |e| e[:title] == "Marked Post" }
    assert_equal "A bold claim", entry[:excerpt]
  end
end
