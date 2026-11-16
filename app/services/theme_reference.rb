# The theme reference pages: admin-only pages that show every element a theme
# styles, written in Markdown and rendered by the same code as a real page.
#
# Everything lives in current/, never in site/. The pages are part of Roe's
# admin, so every install has them, matching the Roe it runs, and nothing
# reaches Site Sync, the static site or the search index.
#
# Collections, post links, product links, product grids and buy buttons read
# their items from the database. So the pages look the same on every site,
# including a new one with no posts or products, the sample posts and products
# in sample_content.yml are inserted for the length of one render and rolled
# back after it, and the site's members, payments and store features answer
# as on for that render. Other requests never see them: SQLite doesn't show a
# connection's uncommitted rows to any other connection. Inserted with
# insert_all, so no model callbacks run (Product#register_category would
# otherwise write the category into site/system/features/store.yml).
module ThemeReference
  DIR = Rails.root.join("app/views/admin/theme_reference")
  PAGES_DIR = DIR.join("pages")
  MEDIA_DIR = DIR.join("media")
  SAMPLE_CONTENT = DIR.join("sample_content.yml")

  # Where the sample media is served from. The Markdown uses this path
  # directly, so it stays readable as Markdown.
  MEDIA_URL = "/admin/themes/reference/media".freeze

  # Every sample record's url_name starts with this, so the page can stop a
  # click on a link to one (it would 404 once the render is rolled back).
  SAMPLE_PREFIX = "theme-reference-".freeze

  # Named after the theme's sections, so a page and a TOC entry share a name.
  Entry = Struct.new(:slug, :title, keyword_init: true)
  PAGES = [
    Entry.new(slug: "text",        title: "Text"),
    Entry.new(slug: "media",       title: "Media"),
    Entry.new(slug: "players",     title: "Players"),
    Entry.new(slug: "cards",       title: "Cards"),
    Entry.new(slug: "collections", title: "Collections"),
    Entry.new(slug: "buttons",     title: "Buttons"),
    Entry.new(slug: "forms",       title: "Forms & Members"),
    Entry.new(slug: "store",       title: "Store"),
    Entry.new(slug: "layout",      title: "Layout")
  ].freeze

  module_function

  def find(slug)
    PAGES.find { |page| page.slug == slug.to_s }
  end

  def markdown(page)
    File.read(PAGES_DIR.join("#{page.slug}.md"))
  end

  # An unsaved Page carrying the reference Markdown, so it goes through the
  # site's page layout (page.txt) and HasMarkdownExtensions#to_html exactly as
  # a real page does.
  def record(page)
    ::Page.new(
      content: markdown(page),
      file_path: PAGES_DIR.join("#{page.slug}.md").to_s,
      metadata: {
        "title" => page.title,
        "url_name" => "#{SAMPLE_PREFIX}#{page.slug}",
        "status" => "published",
        # The paywall form only draws on paid content.
        "audience" => (page.slug == "forms" ? "paid" : "everyone")
      }
    )
  end

  def media_files
    Dir.children(MEDIA_DIR).select { |name| File.file?(MEDIA_DIR.join(name)) }.sort
  end

  # Runs the block with the sample posts and products in the database, then
  # rolls them back, and with every feature answering as on (see
  # SiteFeature.showing_everything), so forms and buttons for features this
  # site has turned off still draw. Returns the block's value.
  def with_sample_content
    result = nil
    SiteFeature.showing_everything do
      ActiveRecord::Base.transaction(requires_new: true) do
        insert_samples
        result = yield
        raise ActiveRecord::Rollback
      end
    end
    result
  end

  def sample_content
    SiteFile.read_yaml(SAMPLE_CONTENT.to_s) || {}
  end

  def insert_samples
    now = Time.current
    content = sample_content
    rows = ->(items, dir) {
      Array(items).map do |item|
        metadata = item.except("body")
        metadata["url_name"] = "#{SAMPLE_PREFIX}#{metadata['url_name']}"
        {
          content: item["body"].to_s,
          metadata: metadata,
          file_path: "#{DIR}/#{dir}/#{metadata['url_name']}.md",
          created_at: now,
          updated_at: now
        }
      end
    }

    posts = rows.call(content["posts"], "posts")
    products = rows.call(content["products"], "products")
    ::Post.insert_all(posts) if posts.any?
    ::Product.insert_all(products) if products.any?
  end
end
