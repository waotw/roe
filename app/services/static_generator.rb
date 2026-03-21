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

    copy_assets(changes[:assets]) if changes[:assets]
    copy_media(changes[:media]) if changes[:media]

    generate_404 if changes[:config]

    save_manifest
    @stats[:end_time] = Time.current
    log_summary

    @stats
  end

  # Generate a single post (for incremental updates)
  def generate_post_by_slug(slug)
    post = Post.find_by(url_name: slug) || Post.find_by(slug: slug)
    return false unless post

    generate_post(post)
    true
  rescue => e
    log_error('post', slug, e)
    false
  end

  # Generate a single page (for incremental updates)
  def generate_page_by_slug(slug)
    page = Page.find_by(url_name: slug) || Page.find_by(slug: slug)
    return false unless page

    generate_page(page)
    true
  rescue => e
    log_error('page', slug, e)
    false
  end

  private

  # ============================================================================
  # SETUP
  # ============================================================================

  def prepare_output_directory
    puts "📁 Preparing output directory..."

    # Create main directories
    [ @output_dir ].each do |dir|
      FileUtils.mkdir_p(dir) unless dir.exist?
    end
  end

  # ============================================================================
  # MANIFEST / DETECT FILE CHANGES FOR GENERATION
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
    puts "   Posts: #{manifest['posts']&.count || 0}"
    puts "   Pages: #{manifest['pages']&.count || 0}"

    manifest
  rescue => e
    puts "   ✗ Failed to load manifest: #{e.message}"
    puts "   #{e.backtrace.first}"
    {}
  end

  def save_manifest
    manifest = {
      generated_at: Time.current.iso8601(6),
      posts: build_content_manifest(Post),
      pages: build_content_manifest(Page),
      documentation: build_content_manifest(Documentation),
      site_config: SiteConfig.first&.updated_at&.iso8601(6),
      assets: asset_checksums
    }

    manifest_path = @output_dir.join('.generation_manifest.json')

    puts "💾 Saving manifest to: #{manifest_path}"
    puts "   Posts: #{manifest[:posts].count}"
    puts "   Pages: #{manifest[:pages].count}"

    File.write(manifest_path, JSON.pretty_generate(manifest))
    puts "   ✓ Manifest saved"
  rescue => e
    puts "   ✗ Failed to save manifest: #{e.message}"
    puts "   #{e.backtrace.first}"
  end

  def asset_checksums
    {
      fonts: dir_checksum(Rails.root.join('site', 'system', 'assets', 'fonts')),
      images: dir_checksum(Rails.root.join('site', 'system', 'assets', 'images')),
      media: dir_checksum(Rails.root.join('site', 'media'))
    }
  end

  def dir_checksum(path)
    return nil unless path.exist?

    files = Dir.glob(path.join('**', '*')).select { |f| File.file?(f) }
    files.map { |f| [ f, File.mtime(f).to_i ] }.to_h
  end

  def detect_changes
    posts = changed_items(Post.not_draft, 'posts')
    pages = changed_items(Page.not_draft, 'pages')
    docs = changed_items(Documentation.not_draft, 'documentation')

    {
      home: home_changed?,
      posts: posts,
      pages: pages,
      documentation: docs,
      collections: posts.any? || pages.any? || @manifest['generated_at'].nil?,
      feeds: posts.any? || @manifest['generated_at'].nil?,
      assets: assets_changed?,
      media: media_changed?,
      config: config_changed?
    }
  end

  def changed_items(scope, type)
    scope.select do |item|
      manifest_entry = @manifest.dig(type, item.id.to_s)

      if manifest_entry.nil?
        true # New item
      else
        # Handle both old format (string) and new format (hash)
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

    # Handle both old and new format
    last_generated = manifest_entry.is_a?(Hash) ? manifest_entry['updated_at'] : manifest_entry

    !last_generated || home.updated_at > Time.parse(last_generated)
  end

  def assets_changed?
    @manifest['assets'] != asset_checksums
  end

  def media_changed?
    @manifest.dig('assets', 'media') != asset_checksums[:media]
  end

  def config_changed?
    last = @manifest['site_config']
    config = SiteConfig.first
    !last || !config || config.updated_at > Time.parse(last)
  end

  def feeds_changed?
    # Already handled in detect_changes
    true
  end

  def build_content_manifest(model)
    # Get all items at once with their url_names
    items = model.pluck(:id, :updated_at, Arel.sql("json_extract(metadata, '$.url_name')"))

    items.map do |id, updated_at, url_name|
      [
        id.to_s,
        {
          updated_at: updated_at.iso8601(6),
          html_file: html_filename_for_type(model.name, url_name)
        }
      ]
    end.to_h
  end

  def html_filename_for_type(model_name, url_name)
    case model_name
    when 'Post'
      "posts/#{url_name}.html"
    when 'Page'
      "#{url_name}.html"
    when 'Documentation'
      "documentation/#{url_name}.html"
    end
  end

  def cleanup_deleted_files
    deleted = 0

    %w[posts pages documentation].each do |type|
      @manifest.fetch(type, {}).each do |id, data|
        model = type.singularize.capitalize.constantize

        unless model.exists?(id.to_i)
          # Handle both old format (string) and new format (hash)
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

    begin
      home_page = Page.find_by("file_path LIKE ?", "%/home.md")

      unless home_page
        Rails.logger.warn "  ⚠ Home page (home.md) not found - run content sync?"
        return
      end

      html = render_with_layout(
        template: 'pages/show',
        assigns: { page: home_page }
      )

      write_file('index.html', html)
      puts "  ✓ Home page generated"
    rescue => e
      log_error('home', nil, e)
    end
  end

  # ============================================================================
  # POSTS
  # ============================================================================

  def generate_posts(posts)
    if posts.empty?
      puts "📝 No post changes detected"
      return
    end

    puts "📝 Generating #{posts.count} changed posts..."

    posts.each do |post|
      begin
        generate_post(post)
        @stats[:posts] += 1
      rescue => e
        log_error('post', post.slug, e)
      end
    end

    puts "  ✓ Generated #{@stats[:posts]} posts"
  end

  def generate_post(post)
    # Use your existing view template which calls post.to_html
    html = render_with_layout(
      template: 'posts/show',
      assigns: { post: post }
    )

    # Posts use /posts/:url_name
    write_file("posts/#{post.url_name}.html", html)
  end

  # ============================================================================
  # PAGES
  # ============================================================================

  def generate_pages(pages)
    if pages.empty?
      puts "📄 No page changes detected"
      return
    end

    puts "📄 Generating #{pages.count} changed pages..."

    pages.each do |page|
      begin
        generate_page(page)
        @stats[:pages] += 1
      rescue => e
        log_error('page', page.slug, e)
      end
    end

    puts "  ✓ Generated #{@stats[:pages]} pages"
  end

  def generate_page(page)
    # Use your existing view template which calls page.to_html
    html = render_with_layout(
      template: 'pages/show',
      assigns: { page: page }
    )

    # Pages use their url_name directly (e.g., /about, /contact)
    write_file("#{page.url_name}.html", html)
  end

  # ============================================================================
  # DOCUMENTATION
  # ============================================================================

  def generate_documentation(docs)
    return unless defined?(Documentation)

    if docs.empty?
      puts "📚 No documentation changes detected"
      return
    end

    puts "📚 Generating #{docs.count} changed documentation pages..."

    docs.each do |doc|
      next if doc.content.blank?

      begin
        generate_documentation_page(doc)
        @stats[:documentation] += 1
      rescue => e
        log_error('documentation', doc.slug, e)
      end
    end

    puts "  ✓ Generated #{@stats[:documentation]} documentation pages"
  end

  def generate_documentation_page(doc)
    html = render_with_layout(
      template: 'documentation/show',
      assigns: { doc: doc }
    )

    write_file("documentation/#{doc.url_name}.html", html)
  end

  # ============================================================================
  # COLLECTION ARCHIVES
  # ============================================================================

  def generate_collection_archives
    puts "📚 Generating collection archives..."

    # Generate /posts archive (all posts)
    generate_posts_archive

    # Generate tag-based collection pages
    generate_tag_collections

    # Generate post-type collections
    generate_type_collections

    puts "  ✓ Generated #{@stats[:collection_pages]} collection pages"
  end

  def generate_posts_archive
    posts = Post.public_posts.by_date
    total_posts = posts.count
    per_page = 20
    total_pages = (total_posts.to_f / per_page).ceil

    total_pages.times do |page_num|
      page = page_num + 1
      page_posts = posts.offset((page - 1) * per_page).limit(per_page)

      html = render_with_layout(
        template: 'collections/archive',
        assigns: {
          items: page_posts,
          collection_title: 'All Posts',
          current_page: page,
          total_pages: total_pages,
          base_url: '/posts'
        }
      )

      if page == 1
        write_file('posts.html', html)
      else
        write_file("posts/page-#{page}.html", html)
      end

      @stats[:collection_pages] += 1
    end
  end

  def generate_tag_collections
    # Get all unique tags efficiently
    tags = Post.public_posts.all_tags

    tags.each do |tag|
      begin
        generate_tag_collection(tag)
      rescue => e
        log_error('tag_collection', tag, e)
      end
    end
  end

  def generate_tag_collection(tag)
    # Use the optimized tagged_with scope
    posts = Post.public_posts.tagged_with(tag).by_date

    total_posts = posts.count
    per_page = 20
    total_pages = (total_posts.to_f / per_page).ceil

    slug = tag.parameterize

    total_pages.times do |page_num|
      page = page_num + 1
      page_posts = posts.offset((page - 1) * per_page).limit(per_page)

      html = render_with_layout(
        template: 'collections/archive',
        assigns: {
          items: page_posts,
          collection_title: "Posts tagged: #{tag}",
          current_page: page,
          total_pages: total_pages,
          base_url: "/collections/#{slug}"
        }
      )

      if page == 1
        write_file("collections/#{slug}.html", html)
      else
        write_file("collections/#{slug}/page-#{page}.html", html)
      end

      @stats[:collection_pages] += 1
    end
  end

  def generate_type_collections
    # Get all unique post types efficiently
    types = Post.public_posts.all_post_types

    types.each do |type|
      begin
        generate_type_collection(type)
      rescue => e
        log_error('type_collection', type, e)
      end
    end
  end

  def generate_type_collection(type)
    # Use the optimized by_type scope
    posts = Post.public_posts.by_type(type).by_date

    total_posts = posts.count
    per_page = 20
    total_pages = (total_posts.to_f / per_page).ceil

    slug = "type-#{type.parameterize}"

    total_pages.times do |page_num|
      page = page_num + 1
      page_posts = posts.offset((page - 1) * per_page).limit(per_page)

      html = render_with_layout(
        template: 'collections/archive',
        assigns: {
          items: page_posts,
          collection_title: "#{type.titleize} Posts",
          current_page: page,
          total_pages: total_pages,
          base_url: "/collections/#{slug}"
        }
      )

      if page == 1
        write_file("collections/#{slug}.html", html)
      else
        write_file("collections/#{slug}/page-#{page}.html", html)
      end

      @stats[:collection_pages] += 1
    end
  end

  # ============================================================================
  # FEEDS
  # ============================================================================

  def generate_feeds
    puts "📡 Generating RSS/Atom feeds..."

    begin
      # RSS 2.0
      rss_xml = render_feed(format: :rss)
      write_file('feed.rss', rss_xml) if rss_xml.present?

      # Atom 1.0
      atom_xml = render_feed(format: :atom)
      write_file('feed.atom', atom_xml) if atom_xml.present?

      puts "  ✓ Generated feeds"
    rescue => e
      log_error('feeds', nil, e)
    end
  end

  def render_feed(format:)
    controller = FeedsController.new
    controller.request = ActionDispatch::TestRequest.create(
      'HTTP_HOST' => site_host,
      'HTTPS' => 'on'
    )
    controller.response = ActionDispatch::TestResponse.new

    case format
    when :rss
      controller.rss
    when :atom
      controller.atom
    end

    controller.response.body
  rescue => e
    Rails.logger.warn "  ⚠ Could not generate #{format} feed: #{e.message}"
    nil
  end

  # ============================================================================
  # ASSETS
  # ============================================================================

  def copy_assets(force = false)
    puts "🎨 Copying changed assets..."

    sync_directory(
      Rails.root.join('site', 'system', 'assets', 'fonts'),
      @output_dir.join('system', 'fonts')
    )

    sync_directory(
      Rails.root.join('site', 'system', 'assets', 'images'),
      @output_dir.join('system', 'images')
    )

    puts "  ✓ Assets synced"
  end

  def copy_media(force = false)
    puts "🖼️  Copying changed media..."

    sync_directory(
      Rails.root.join('site', 'media'),
      @output_dir.join('media')
    )

    puts "  ✓ Media synced"
  end

  def sync_directory(source, dest)
    return unless source.exist?

    FileUtils.mkdir_p(dest)

    copied = 0
    skipped = 0
    deleted = 0

    # Track what should exist
    source_files = Set.new

    Dir.glob(source.join('**', '*')).each do |source_file|
      next unless File.file?(source_file)

      relative_path = Pathname.new(source_file).relative_path_from(source)
      source_files << relative_path.to_s
      dest_file = dest.join(relative_path)

      # Copy if destination doesn't exist or source is newer
      if !dest_file.exist? || File.mtime(source_file) > File.mtime(dest_file)
        FileUtils.mkdir_p(dest_file.dirname)
        FileUtils.cp(source_file, dest_file)
        copied += 1
      else
        skipped += 1
      end
    end

    # Remove orphaned files in destination
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

    begin
      html = render_with_layout(
        template: 'errors/not_found'
      )

      write_file('404.html', html)
      puts "  ✓ 404 page generated"
    rescue => e
      Rails.logger.warn "  ⚠ Could not generate custom 404, using basic: #{e.message}"
      basic_404 = <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <title>404 - Page Not Found</title>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body>
          <h1>404 - Page Not Found</h1>
          <p>The page you're looking for doesn't exist.</p>
          <p><a href="/">Return to home page</a></p>
        </body>
        </html>
      HTML
      write_file('404.html', basic_404)
    end
  end

  # ============================================================================
  # RENDERING HELPERS
  # ============================================================================

  def render_with_layout(template: nil, controller: nil, action: nil, assigns: {})
    # Determine template path
    template_path = if template
      template
    elsif controller && action
      "#{controller}/#{action}"
    else
      raise ArgumentError, "Must provide either template or controller+action"
    end

    # Render using ApplicationController which has access to all helpers
    ApplicationController.render(
      template: template_path,
      assigns: assigns,
      layout: 'site'
    )
  end

  def site_host
    @site_host ||= begin
      config = SiteConfig.first
      config&.url&.gsub(%r{https?://}, '') || 'localhost'
    end
  end

  # ============================================================================
  # FILE OPERATIONS
  # ============================================================================

  def write_file(relative_path, content)
    full_path = @output_dir.join(relative_path)

    # Create directory if needed
    FileUtils.mkdir_p(full_path.dirname)

    # Post-process HTML (only for HTML files)
    if relative_path.end_with?('.html')
      content = post_process_html(content, relative_path)
    end

    # Write file
    File.write(full_path, content)
  end

  def post_process_html(html, relative_path)
    doc = Nokogiri::HTML(html)

    # Convert absolute URLs to relative
    rewrite_urls(doc, relative_path)

    # Add generator meta tag
    add_generator_meta(doc)

    doc.to_html
  end

  def rewrite_urls(doc, current_path)
    # Calculate relative depth
    depth = current_path.count('/')
    prefix = depth > 0 ? ('../' * depth) : './'

    # Only rewrite page/post links (not media, fonts, assets, system)
    doc.css('a[href^="/"]').each do |link|
      href = link['href']

      # Skip URLs that should remain absolute (they're already in the right place)
      next if href.start_with?('/media/', '/system/', '/assets/')

      clean_href = href[1..-1]

      # Handle root
      if clean_href.empty? || clean_href == 'index'
        link['href'] = "#{prefix}index.html"
      elsif !clean_href.match?(/\.\w+$/)
        link['href'] = "#{prefix}#{clean_href}.html"
      end
    end
  end

  def add_generator_meta(doc)
    meta = Nokogiri::XML::Node.new('meta', doc)
    meta['name'] = 'generator'
    meta['content'] = 'Custom Rails CMS Static Generator'

    head = doc.at_css('head')
    head&.add_child(meta)
  end

  # ============================================================================
  # ERROR HANDLING & LOGGING
  # ============================================================================

  def log_error(type, identifier, error)
    message = identifier ? "#{type} '#{identifier}'" : type
    Rails.logger.error "  ✗ Failed to generate #{message}: #{error.message}"
    Rails.logger.error "    #{error.backtrace.first}"

    @stats[:errors] << {
      type: type,
      identifier: identifier,
      message: error.message
    }
  end

  def log_summary
    duration = @stats[:end_time] - @stats[:start_time]

    puts ""
    puts "=" * 60
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
      Rails.logger.warn ""
      Rails.logger.warn "⚠️  Errors encountered:"
      @stats[:errors].each do |error|
        identifier = error[:identifier] ? " (#{error[:identifier]})" : ""
        Rails.logger.warn "  - #{error[:type]}#{identifier}: #{error[:message]}"
      end
    end
  end
end
