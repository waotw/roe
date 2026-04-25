# StaticGenerator - Incremental static site generator for Roe CMS
#
# Generates a complete static HTML site from Markdown content with smart
# incremental builds that only regenerate changed content.
#
# Architecture:
#   - Source of truth: Markdown files in /site directory
#   - Database: Synchronized cache for querying/filtering
#   - Output: Static HTML files in /public directory
#   - Change detection: Manifest-based tracking with microsecond timestamps
#
# Incremental Build Strategy:
#   - Tracks content, configs, layouts, and assets via generation manifest
#   - Only regenerates files when source content has changed
#   - Config/layout changes trigger full site regeneration
#   - Asset sync only copies new/modified files
#
# Manifest Format (.generation_manifest.json):
#   {
#     "generated_at": "2026-03-22T20:48:30.856227Z",
#     "posts": { "1": { "updated_at": "...", "html_file": "posts/slug.html" } },
#     "pages": { "2": { "updated_at": "...", "html_file": "about.html" } },
#     "documentation": { ... },
#     "configs": {
#       "site": "2026-03-22T...",
#       "defaults/collections": "2026-03-22T...",
#       "defaults/cards": "2026-03-22T..."
#     },
#     "layouts": { "/path/to/navigation.md": 1234567890, ... },
#     "assets": { "fonts": {...}, "images": {...}, "media": {...} }
#   }
#
# Generated URL Structure:
#   - Home: /index.html
#   - Posts: /posts/{url_name}.html
#   - Pages: /{url_name}.html
#   - Documentation: /documentation/{url_name}.html
#   - Post archive: /posts.html, /posts/page-2.html, etc.
#   - Filtered collections: /collections/{slug}.html, /collections/{slug}/page-2.html
#   - Feeds: /feed.rss, /feed.atom
#   - Assets: /system/fonts/*, /system/images/*, /media/*
#
# Usage:
#   generator = StaticGenerator.new
#   stats = generator.generate_all
#   # => { posts: 10, pages: 5, collections: 15, duration: 0.5, errors: [] }
#
# Performance:
#   - Full generation: ~0.5s for typical site
#   - Incremental (no changes): ~0.05s
#   - Single post update: ~0.1s
#
class StaticGenerator
  attr_reader :output_dir, :stats

  def initialize(output_dir: Rails.root.join('public'))
    @output_dir = Pathname.new(output_dir)
    @stats = {
      posts: 0,
      pages: 0,
      documentation: 0,
      collections: 0,
      collection_pages: 0,
      errors: [],
      start_time: nil,
      end_time: nil
    }
  end

  def generate_all
    @stats[:start_time] = Time.current
    @manifest = load_manifest

    puts "🚀 Starting static site generation..."

    prepare_output_directory

    # Check what changed
    changes = detect_changes

    # Clean up deleted content
    cleanup_deleted_files

    # Reload only the configs that actually changed
    if changes[:changed_configs][:site]
      puts "  🔄 Reloading site config..."
      SiteConfig.reload!('site')
    end

    if changes[:changed_configs][:collections]
      puts "  🔄 Reloading collections config..."
      SiteConfig.reload!('defaults/collections')
    end

    if changes[:changed_configs][:podcast]
      puts "  🔄 Reloading podcast config..."
      SiteConfig.reload!('features/podcast')
      PodcastConfig.reload!
    end

    if changes[:changed_configs][:members]
      puts "  🔄 Reloading members config..."
      SiteConfig.reload!('defaults/members')
      Rails.cache.clear
    end

    # Log what changed
    puts "📊 Change detection:"
    puts "  Home: #{changes[:home] ? 'changed' : 'unchanged'}"
    puts "  Posts: #{changes[:posts].count} changed"
    puts "  Pages: #{changes[:pages].count} changed"
    puts "  Documentation: #{changes[:documentation].count} changed"
    puts "  Collections: #{changes[:collections] ? 'regenerate' : 'skip'}"
    puts "  Feeds: #{changes[:feeds] ? 'regenerate' : 'skip'}"
    puts "  Assets: #{changes[:assets] ? 'changed' : 'unchanged'}"
    puts "  Media: #{changes[:media] ? 'changed' : 'unchanged'}"

    # Generate based on what changed
    generate_home if changes[:home]
    generate_posts(changes[:posts]) if changes[:posts].any?
    generate_pages(changes[:pages]) if changes[:pages].any?
    generate_documentation(changes[:documentation]) if changes[:documentation].any?
    generate_collection_archives if changes[:collections]
    generate_feeds if changes[:feeds]
    generate_podcast_feeds if changes[:podcast_feeds]

    copy_assets if changes[:assets]
    copy_media if changes[:media]

    generate_404 if changes[:config]

    save_manifest
    @stats[:end_time] = Time.current
    log_summary

    @stats
  end

  private

  # ============================================================================
  # SETUP
  # ============================================================================

  def prepare_output_directory
    puts "📁 Preparing output directory..."
    [ @output_dir ].each do |dir|
      FileUtils.mkdir_p(dir) unless dir.exist?
    end
  end

  # ============================================================================
  # MANIFEST / CHANGE DETECTION
  # ============================================================================

  def load_manifest
    manifest_file = @output_dir.join('.generation_manifest.json')

    puts "📖 Loading manifest from: #{manifest_file}"

    unless manifest_file.exist?
      puts "   ⊘ No manifest found (first run)"
      return {}
    end

    manifest = JSON.parse(File.read(manifest_file))
    puts "   ✓ Loaded manifest (generated at: #{manifest['generated_at']})"

    manifest
  rescue => e
    puts "   ✗ Failed to load manifest: #{e.message}"
    {}
  end

  def save_manifest
    manifest = {
      generated_at: Time.current.iso8601(6),
      posts: build_content_manifest(Post),
      pages: build_content_manifest(Page),
      documentation: build_content_manifest(Documentation),
      configs: {
        'site' => SiteConfig.find_by("file_path LIKE ?", "%site.yml")&.updated_at&.iso8601(6),
        'defaults/collections' => SiteConfig.find_by("file_path LIKE ?", "%collections.yml")&.updated_at&.iso8601(6),
        'defaults/cards' => SiteConfig.find_by("file_path LIKE ?", "%cards.yml")&.updated_at&.iso8601(6),
        'defaults/podcast' => SiteConfig.find_by("file_path LIKE ?", "%podcast.yml")&.updated_at&.iso8601(6),
        'defaults/members' => SiteConfig.find_by("file_path LIKE ?", "%members.yml")&.updated_at&.iso8601(6)
      },
      layouts: layout_checksums,
      assets: asset_checksums
    }

    manifest_path = @output_dir.join('.generation_manifest.json')
    puts "💾 Saving manifest to: #{manifest_path}"
    File.write(manifest_path, JSON.pretty_generate(manifest))
    puts "   ✓ Manifest saved"
  rescue => e
    puts "   ✗ Failed to save manifest: #{e.message}"
  end

  def detect_changes
    posts = changed_items(Post.not_draft, 'posts')
    pages = changed_items(Page.not_draft, 'pages')
    docs = changed_items(Documentation.not_draft, 'documentation')

    podcast_posts = posts.select { |p| p.metadata['post_type'] == 'podcast' }

    # Track which specific configs changed
    site_config_changed = config_file_changed?('site')
    collections_config_changed = config_file_changed?('defaults/collections')
    cards_config_changed = config_file_changed?('defaults/cards')
    podcast_config_changed = config_file_changed?('defaults/podcast')
    members_config_changed = config_file_changed?('defaults/members')

    global_changed = site_config_changed || collections_config_changed || cards_config_changed || members_config_changed || layouts_changed?

    {
      home: home_changed? || site_config_changed || collections_config_changed || members_config_changed || layouts_changed?,
      posts: global_changed ? Post.not_draft.to_a : posts,
      pages: global_changed ? Page.not_draft.to_a : pages,
      documentation: global_changed ? Documentation.not_draft.to_a : docs,
      collections: collections_config_changed || members_config_changed || posts.any? || pages.any? || @manifest['generated_at'].nil?,
      feeds: site_config_changed || posts.any? || @manifest['generated_at'].nil?,
      podcast_feeds: podcast_config_changed || podcast_posts.any? || @manifest['generated_at'].nil?,
      assets: assets_changed?,
      media: media_changed?,
      config: global_changed,

      # Track which configs actually changed
      changed_configs: {
        site: site_config_changed,
        collections: collections_config_changed,
        cards: cards_config_changed,
        podcast: podcast_config_changed,
        members: members_config_changed
      }
    }
  end

  def changed_items(scope, type)
    scope.select do |item|
      manifest_entry = @manifest.dig(type, item.id.to_s)
      if manifest_entry.nil?
        true
      else
        last_generated = manifest_entry.is_a?(Hash) ? manifest_entry['updated_at'] : manifest_entry
        !last_generated || item.updated_at > Time.parse(last_generated)
      end
    end
  end

  def home_changed?
    home = Page.find_by("file_path LIKE ?", "%/home.md")
    return true unless home

    manifest_entry = @manifest.dig('pages', home.id.to_s)
    return true unless manifest_entry

    last_generated = manifest_entry.is_a?(Hash) ? manifest_entry['updated_at'] : manifest_entry
    !last_generated || home.updated_at > Time.parse(last_generated)
  end

  def podcast_config_changed?
    config_file_changed?('defaults/podcast')
  end

  def config_changed?
    # Check all config files
    site_changed = config_file_changed?('site')
    collections_changed = config_file_changed?('defaults/collections')
    cards_changed = config_file_changed?('defaults/cards')

    site_changed || collections_changed || cards_changed
  end

  def config_file_changed?(config_type)
    last = @manifest.dig('configs', config_type)
    config = SiteConfig.find_by("file_path LIKE ?", "%#{config_type}.yml")

    if last && config
      manifest_time = Time.parse(last)
      db_time = config.updated_at
    end

    changed = !last || !config || config.updated_at > Time.parse(last)

    changed
  end

  def layouts_changed?
    @manifest['layouts'] != layout_checksums
  end

  def assets_changed?
    @manifest['assets'] != asset_checksums
  end

  def media_changed?
    @manifest.dig('assets', 'media') != asset_checksums[:media]
  end

  def layout_checksums
    layout_dir = Rails.root.join('site', 'layout')
    return nil unless layout_dir.exist?

    Dir.glob(layout_dir.join('*.md')).map { |f| [ f, File.mtime(f).to_i ] }.to_h
  end

  def asset_checksums
    {
      fonts: dir_checksum(Rails.root.join('site', 'system', 'assets', 'fonts')),
      images: dir_checksum(Rails.root.join('site', 'system', 'assets', 'images')),
      media: dir_checksum(Rails.root.join('site', 'media')),
      theme: dir_checksum(Rails.root.join('site', 'theme'))
    }
  end

  def dir_checksum(path)
    return nil unless path.exist?
    files = Dir.glob(path.join('**', '*')).select { |f| File.file?(f) }
    files.map { |f| [ f, File.mtime(f).to_i ] }.to_h
  end

  def build_content_manifest(model)
    items = model.pluck(:id, :updated_at, Arel.sql("json_extract(metadata, '$.url_name')"))
    items.map do |id, updated_at, url_name|
      [ id.to_s, {
        updated_at: updated_at.iso8601(6),
        html_file: html_filename_for_type(model.name, url_name)
      } ]
    end.to_h
  end

  def html_filename_for_type(model_name, url_name)
    case model_name
    when 'Post' then "posts/#{url_name}.html"
    when 'Page' then "#{url_name}.html"
    when 'Documentation' then "documentation/#{url_name}.html"
    end
  end

  def cleanup_deleted_files
    deleted = 0
    %w[posts pages documentation].each do |type|
      @manifest.fetch(type, {}).each do |id, data|
        model = type.singularize.capitalize.constantize
        unless model.exists?(id.to_i)
          html_file = data.is_a?(Hash) ? data['html_file'] : nil
          if html_file
            file_to_delete = @output_dir.join(html_file)
            if file_to_delete.exist?
              File.delete(file_to_delete)
              deleted += 1
            end
          end
        end
      end
    end
    puts "🗑️  Deleted #{deleted} orphaned files" if deleted > 0
  end

  # ============================================================================
  # HOME PAGE
  # ============================================================================

  def generate_home
    puts "🏠 Generating home page..."
    home_page = Page.find_by("file_path LIKE ?", "%/home.md")

    unless home_page
      puts "  ⚠ Home page (home.md) not found"
      return
    end

    html = render_with_layout(template: 'pages/show', assigns: { page: home_page })
    write_file('index.html', html)
    puts "  ✓ Home page generated"
  rescue => e
    log_error('home', nil, e)
  end

  # ============================================================================
  # POSTS
  # ============================================================================

  def generate_posts(posts)
    return puts "📝 No post changes detected" if posts.empty?

    puts "📝 Generating #{posts.count} changed posts..."
    posts.each do |post|
      generate_post(post)
      @stats[:posts] += 1
    rescue => e
      log_error('post', post.slug, e)
    end
    puts "  ✓ Generated #{@stats[:posts]} posts"
  end

  def generate_post(post)
    html = render_with_layout(template: 'posts/show', assigns: { post: post })
    write_file("posts/#{post.url_name}.html", html)
  end

  # ============================================================================
  # PAGES
  # ============================================================================

  def generate_pages(pages)
    return puts "📄 No page changes detected" if pages.empty?

    puts "📄 Generating #{pages.count} changed pages..."
    pages.each do |page|
      generate_page(page)
      @stats[:pages] += 1
    rescue => e
      log_error('page', page.slug, e)
    end
    puts "  ✓ Generated #{@stats[:pages]} pages"
  end

  def generate_page(page)
    html = render_with_layout(template: 'pages/show', assigns: { page: page })
    write_file("#{page.url_name}.html", html)
  end

  # ============================================================================
  # DOCUMENTATION
  # ============================================================================

  def generate_documentation(docs)
    return unless defined?(Documentation)
    return puts "📚 No documentation changes detected" if docs.empty?

    puts "📚 Generating #{docs.count} changed documentation pages..."
    docs.each do |doc|
      next if doc.content.blank?
      generate_documentation_page(doc)
      @stats[:documentation] += 1
    rescue => e
      log_error('documentation', doc.slug, e)
    end
    puts "  ✓ Generated #{@stats[:documentation]} documentation pages"
  end

  def generate_documentation_page(doc)
    html = render_with_layout(template: 'documentation/show', assigns: { doc: doc })
    write_file("documentation/#{doc.url_name}.html", html)
  end

  # ============================================================================
  # COLLECTION ARCHIVES
  # ============================================================================

  def generate_collection_archives
    puts "📚 Generating collection archives..."

    generate_posts_archive
    generate_embedded_collections

    puts "  ✓ Generated #{@stats[:collection_pages]} collection pages"
  end

  def generate_posts_archive
    posts = Post.published.regular_posts.by_date

    generate_paginated_collection(
      items: posts,
      slug: 'posts',
      title: 'All Posts',
      per_page: default_per_page
    )
  end

  def generate_embedded_collections
    collections = extract_collection_configs

    collections.each do |config|
      generate_named_collection(config)
    rescue => e
      log_error('collection', config[:heading] || 'unnamed', e)
    end
  end

  def extract_collection_configs
    configs = []

    [ Post, Page ].each do |model|
      model.not_draft.each do |item|
        item.content.scan(/```collection\r?\n(.*?)```/m) do
          config = parse_collection_config($1)
          if config[:show_more] == 'true' || config[:show_more] == true
            configs << config
          end
        end
      end
    end

    configs.uniq { |c| generate_collection_url_path(c) }
  end

  def parse_collection_config(text)
    config = {}
    text.split("\n").each do |line|
      next if line.strip.empty?
      key, value = line.split(':', 2).map(&:strip)
      config[key.to_sym] = value if key && value
    end
    config
  end

  def generate_named_collection(config)
    slug = generate_collection_slug(config)
    items = fetch_collection_items(config)

    generate_paginated_collection(
      items: items,
      slug: slug,
      title: config[:heading] || generate_title_from_config(config),
      per_page: default_per_page
    )
  end

  def default_per_page
    SiteConfig.default('collections', 'items_per_page')&.to_i || 20
  end

  def generate_collection_slug(config)
    heading = config[:heading]
    tags = config[:tags]
    post_type = config[:post_type] unless config[:post_type] == 'all'
    podcast_key = config[:podcast]

    if heading.present?
      heading.parameterize
    elsif post_type || tags.present? || podcast_key.present?
      segments = []
      segments << "type-#{post_type.parameterize}" if post_type
      segments << "podcast-#{podcast_key.parameterize}" if podcast_key.present?

      if tags.present?
        positive_tags = tags.split(',').map(&:strip).reject { |t| t.start_with?('-') }
        segments << positive_tags.map(&:parameterize).join(',') if positive_tags.any?
      end

      segments.join('/')
    else
      'all'
    end
  end

  def generate_collection_url_path(config)
    slug = generate_collection_slug(config)
    "/collections/#{slug}"
  end

  def fetch_collection_items(config)
    source = config[:source] || 'posts'
    tags = config[:tags]
    post_type = config[:post_type] unless config[:post_type] == 'all'
    order = config[:order] || 'date'
    podcast_key = config[:podcast]

    items = case source
    when 'posts'
      collection = Post.published.regular_posts
      collection = collection.by_type(post_type) if post_type
      collection = collection.where("json_extract(metadata, '$.podcast') = ?", podcast_key.strip) if podcast_key.present?
      collection = apply_tag_filters(collection, tags) if tags
      collection
    when 'pages'
      Page.public_pages
    when 'documentation'
      Documentation.not_draft
    else
      Post.published.regular_posts
    end

    # Apply paid content filter (before ordering!)
    items = CollectionMembersFilter.filter(items, config)

    apply_collection_order(items, order)
  end

  def apply_tag_filters(collection, tag_string)
    return collection if tag_string.blank?

    tags = tag_string.split(',').map(&:strip)
    positive_tags = tags.reject { |t| t.start_with?('-') }
    negative_tags = tags.select { |t| t.start_with?('-') }.map { |t| t[1..-1] }

    collection = collection.tagged_with(positive_tags) if positive_tags.any?

    negative_tags.each do |neg_tag|
      collection = collection.where(
        "json_extract(metadata, '$.tags') IS NULL OR json_extract(metadata, '$.tags') NOT LIKE ?",
        "%#{neg_tag}%"
      )
    end

    collection
  end

  def apply_collection_order(items, order_by)
    case order_by
    when 'filename'
      items.to_a.sort_by do |item|
        filename = File.basename(item.file_path, '.md')
        filename =~ /^(\d+)/ ? [ $1.to_i, filename ] : [ Float::INFINITY, filename ]
      end
    when 'title'
      items.order(Arel.sql("json_extract(metadata, '$.title') ASC"))
    when 'date-asc'
      items.order(Arel.sql("json_extract(metadata, '$.date') ASC NULLS LAST"))
    else
      items.order(Arel.sql("json_extract(metadata, '$.date') DESC NULLS LAST"))
    end
  end

  def generate_title_from_config(config)
    if config[:tags].present?
      tags = config[:tags].split(',').map(&:strip).reject { |t| t.start_with?('-') }
      tags.map(&:titleize).join(', ')
    elsif config[:post_type].present?
      pluralize_post_type(config[:post_type])
    else
      'Collection'
    end
  end

  def pluralize_post_type(type)
    # Media types remain singular
    uncountable = %w[music audio video]

    if uncountable.include?(type.downcase)
      type.titleize
    else
      type.titleize.pluralize
    end
  end

  def generate_paginated_collection(items:, slug:, title:, per_page: 20)
    items_array = items.is_a?(Array) ? items : items.to_a
    total_items = items_array.count
    total_pages = (total_items.to_f / per_page).ceil

    # Determine if this is a root-level archive or a filtered collection
    is_root_archive = slug == 'posts'
    base_path = is_root_archive ? slug : "collections/#{slug}"

    total_pages.times do |page_num|
      page = page_num + 1
      page_items = items_array[(page - 1) * per_page, per_page] || []

      html = render_with_layout(
        template: 'collections/show',
        assigns: {
          page_heading: title,
          page_description: 'latest',
          items: page_items,
          page: page,
          total_pages: total_pages,
          base_url: "/#{base_path}"
        }
      )

      if page == 1
        write_file("#{base_path}.html", html)
      else
        write_file("#{base_path}/page-#{page}.html", html)
      end

      @stats[:collection_pages] += 1
    end
  end

  # ============================================================================
  # FEEDS
  # ============================================================================

  def generate_feeds
    puts "📡 Generating RSS/Atom feeds..."

    rss_xml = render_feed(format: :rss)
    write_file('feed.rss', rss_xml) if rss_xml.present?

    atom_xml = render_feed(format: :atom)
    write_file('feed.atom', atom_xml) if atom_xml.present?

    puts "  ✓ Generated feeds"
  rescue => e
    log_error('feeds', nil, e)
  end

  def generate_podcast_feeds
    puts "🎙️  Generating podcast RSS feeds..."

    podcast_keys = PodcastConfig.podcast_keys
    return puts "  ⊘ No podcasts configured" if podcast_keys.empty?

    podcast_keys.each do |podcast_key|
      generate_podcast_feed(podcast_key)
    rescue => e
      log_error('podcast_feed', podcast_key, e)
    end

    puts "  ✓ Generated #{podcast_keys.count} podcast feeds"
  end

  def generate_podcast_feed(podcast_key)
    podcast_config = PodcastConfig.get(podcast_key)
    episodes = Post.published
      .where("json_extract(metadata, '$.post_type') = ?", 'podcast')
      .where("json_extract(metadata, '$.podcast') = ?", podcast_key)
      .order(Arel.sql("json_extract(metadata, '$.date') DESC"))

    feed_xml = FeedGenerator.new(
      posts: episodes,
      format: :podcast,
      site_config: {
        title: podcast_config['title'],
        description: podcast_config['description'],
        url: "https://#{site_host}",
        author: podcast_config['author']
      },
      podcast_config: podcast_config
    ).generate

    write_file("podcast/#{podcast_key}.xml", feed_xml)
  end

  def render_feed(format:)
    controller = FeedsController.new
    controller.request = ActionDispatch::TestRequest.create('HTTP_HOST' => site_host, 'HTTPS' => 'on')
    controller.response = ActionDispatch::TestResponse.new

    case format
    when :rss then controller.rss
    when :atom then controller.atom
    end

    controller.response.body
  rescue => e
    puts "  ⚠ Could not generate #{format} feed: #{e.message}"
    nil
  end

  # ============================================================================
  # ASSETS & MEDIA
  # ============================================================================

  def copy_assets
    puts "🎨 Copying changed assets..."
    sync_directory(Rails.root.join('site', 'system', 'assets', 'fonts'), @output_dir.join('system', 'fonts'))
    sync_directory(Rails.root.join('site', 'system', 'assets', 'images'), @output_dir.join('system', 'images'))
    sync_directory(Rails.root.join('site', 'theme'), @output_dir.join('theme'))
    puts "  ✓ Assets synced"
  end

  def copy_media
    puts "🖼️  Copying changed media..."
    sync_directory(Rails.root.join('site', 'media'), @output_dir.join('media'))
    puts "  ✓ Media synced"
  end

  def sync_directory(source, dest)
    return unless source.exist?

    FileUtils.mkdir_p(dest)
    copied = skipped = deleted = 0
    source_files = Set.new

    Dir.glob(source.join('**', '*')).each do |source_file|
      next unless File.file?(source_file)

      relative_path = Pathname.new(source_file).relative_path_from(source)
      source_files << relative_path.to_s
      dest_file = dest.join(relative_path)

      if !dest_file.exist? || File.mtime(source_file) > File.mtime(dest_file)
        FileUtils.mkdir_p(dest_file.dirname)
        FileUtils.cp(source_file, dest_file)
        copied += 1
      else
        skipped += 1
      end
    end

    Dir.glob(dest.join('**', '*')).each do |dest_file|
      next unless File.file?(dest_file)
      relative_path = Pathname.new(dest_file).relative_path_from(dest).to_s
      unless source_files.include?(relative_path)
        File.delete(dest_file)
        deleted += 1
      end
    end

    puts "     Copied: #{copied}, Skipped: #{skipped}, Deleted: #{deleted}"
  end

  # ============================================================================
  # 404 PAGE
  # ============================================================================

  def generate_404
    puts "🔍 Generating 404 page..."
    html = render_with_layout(template: 'errors/not_found')
    write_file('404.html', html)
    puts "  ✓ 404 page generated"
  rescue => e
    puts "  ⚠ Using basic 404"
    write_file('404.html', basic_404_html)
  end

  def basic_404_html
    <<~HTML
      <!DOCTYPE html>
      <html><head><title>404 - Page Not Found</title></head>
      <body><h1>404 - Page Not Found</h1><p><a href="/">Return home</a></p></body>
      </html>
    HTML
  end

  # ============================================================================
  # RENDERING & FILE OPERATIONS
  # ============================================================================

  def render_with_layout(template:, assigns: {})
    ApplicationController.render(
      template: template,
      assigns: assigns.merge(static_generation: true),
      layout: 'site'
    )
  rescue ActionController::UrlGenerationError => e
    # Extract context from error
    context_info = [ "Template: #{template}" ]

    # Identify which content item is being rendered
    if assigns[:post]
      context_info << "Post: '#{assigns[:post].title}' (#{assigns[:post].file_path})"
    elsif assigns[:page]
      context_info << "Page: '#{assigns[:page].title}' (#{assigns[:page].file_path})"
    elsif assigns[:doc]
      context_info << "Doc: '#{assigns[:doc].title}' (#{assigns[:doc].file_path})"
    elsif assigns[:items]&.any?
      context_info << "Collection with #{assigns[:items].count} items"
    end

    # Extract the parameter causing the issue
    if e.message.match(/filename=>"([^"]*)"/)
      param_value = $1
      context_info << "Problem: Empty filename parameter (filename='#{param_value}')"
      context_info << "💡 Check for empty image/media/audio/video fields in metadata"
    end

    puts "\n" + "=" * 70
    puts "❌ URL GENERATION ERROR"
    puts "=" * 70
    context_info.each { |info| puts "   #{info}" }
    puts "\n   Error: #{e.message}"
    puts "=" * 70 + "\n"

    raise e # Re-raise to stop generation
  rescue StandardError => e
    puts "\n" + "=" * 70
    puts "❌ RENDERING ERROR"
    puts "=" * 70
    puts "   Template: #{template}"
    puts "   Error: #{e.class}: #{e.message}"
    if e.backtrace
      puts "\n   Backtrace:"
      e.backtrace.first(5).each { |line| puts "      #{line}" }
    end
    puts "=" * 70 + "\n"

    raise e
  end

  def site_host
    @site_host ||= SiteConfig.first&.config&.dig('url')&.gsub(%r{https?://}, '') || 'localhost'
  end

  def write_file(relative_path, content)
    full_path = @output_dir.join(relative_path)
    FileUtils.mkdir_p(full_path.dirname)
    content = post_process_html(content, relative_path) if relative_path.end_with?('.html')
    File.write(full_path, content)
  end

  def post_process_html(html, relative_path)
    doc = Nokogiri::HTML(html)
    rewrite_urls(doc, relative_path)
    add_generator_meta(doc)
    doc.to_html
  end

  def rewrite_urls(doc, current_path)
    depth = current_path.count('/')
    prefix = depth > 0 ? ('../' * depth) : './'

    doc.css('a[href^="/"]').each do |link|
      href = link['href']
      next if href.start_with?('/media/', '/system/', '/assets/')

      clean_href = href[1..-1]

      # Keep root path as-is (don't convert / to /index.html)
      if clean_href.empty?
        link['href'] = prefix.chomp('./') + '/'
      elsif clean_href == 'index'
        link['href'] = prefix.chomp('./') + '/'
      elsif !clean_href.match?(/\.\w+$/)
        link['href'] = "#{prefix}#{clean_href}.html"
      end
    end
  end

  def add_generator_meta(doc)
    meta = Nokogiri::XML::Node.new('meta', doc)
    meta['name'] = 'generator'
    meta['content'] = 'Roe CMS'
    doc.at_css('head')&.add_child(meta)
  end

  # ============================================================================
  # ERROR HANDLING & LOGGING
  # ============================================================================

  def log_error(type, identifier, error)
    message = identifier ? "#{type} '#{identifier}'" : type
    puts "  ✗ Failed to generate #{message}: #{error.message}"
    @stats[:errors] << { type: type, identifier: identifier, message: error.message }
  end

  def log_summary
    duration = @stats[:end_time] - @stats[:start_time]
    puts "\n" + "=" * 60
    puts "✨ Static site generation complete!"
    puts "=" * 60
    puts "  Posts:            #{@stats[:posts]}"
    puts "  Pages:            #{@stats[:pages]}"
    puts "  Documentation:    #{@stats[:documentation]}"
    puts "  Collections:      #{@stats[:collection_pages]}"
    puts "  Errors:           #{@stats[:errors].count}"
    puts "  Duration:         #{duration.round(2)}s"
    puts "  Output:           #{@output_dir}"
    puts "=" * 60

    if @stats[:errors].any?
      puts "\n⚠️  Errors encountered:"
      @stats[:errors].each { |e| puts "  - #{e[:type]}: #{e[:message]}" }
    end
  end
end
