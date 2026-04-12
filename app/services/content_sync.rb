class ContentSync
  def self.sync_all
    new.sync_all
  end

  def sync_all
    sync_site_config
    sync_defaults
    sync_posts
    sync_pages
    sync_documentation
    sync_media
    sync_products
  end

  def sync_posts
    relative_paths = Dir.glob("site/posts/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    puts "\n📚 Found #{markdown_files.count} markdown files in site/posts"

    # Handle orphaned records and detect renames
    handle_orphaned_posts(markdown_files)

    puts "=" * 60

    success_count = 0
    error_count = 0
    error_files = []
    warning_files = []

    markdown_files.each do |file_path|
      result = self.class.sync_file(file_path)

      case result
      when :success
        success_count += 1
      when :error
        error_count += 1
        error_files << File.basename(file_path)
      when :warning
        success_count += 1
        warning_files << File.basename(file_path)
      end
    end

    puts "=" * 60

    # Summary with visual separation
    if error_count > 0 || warning_files.any?
      puts "\n⚠️  SYNC SUMMARY"
      puts "-" * 60

      if error_files.any?
        puts "❌ ERRORS (#{error_count}):"
        error_files.each { |file| puts "   • #{file}" }
        puts ""
      end

      if warning_files.any?
        puts "⚠️  WARNINGS (#{warning_files.count}):"
        warning_files.each { |file| puts "   • #{file}" }
        puts ""
      end
    end

    puts "✅ Sync complete! #{success_count} synced, #{error_count} errors\n\n"
  end

  def sync_pages
    relative_paths = Dir.glob("site/pages/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    return if markdown_files.empty?

    puts "\n📄 Found #{markdown_files.count} markdown files in site/pages"

    # Handle orphaned pages
    handle_orphaned_pages(markdown_files)

    puts "=" * 60

    success_count = 0
    error_count = 0

    markdown_files.each do |file_path|
      result = sync_page_file(file_path)

      case result
      when :success
        success_count += 1
      when :error
        error_count += 1
      end
    end

    puts "=" * 60
    puts "✅ Pages sync complete! #{success_count} synced, #{error_count} errors\n\n"
  end

  def sync_media
    # Sync all media types (images, audio, video)
    media_files = Dir.glob("site/media/**/*.{jpg,jpeg,png,gif,webp,svg,bmp,mp3,m4a,wav,ogg,flac,aac,mp4,webm,ogv,mov,avi,mkv}")

    puts "\n🎬 Found #{media_files.count} media files"

    # Handle orphaned media
    handle_orphaned_media(media_files)

    puts "=" * 60

    success_count = 0

    media_files.each do |file_path|
      web_path = file_path.sub('site', '')

      unless Medium.exists?(file_path: web_path)
        media_type = File.extname(file_path).delete('.').downcase

        Medium.create!(
          file_path: web_path,
          media_type: media_type,  # Model's normalize_media_type will categorize it
          uploaded_at: File.mtime(file_path)
        )

        puts "  ✓ Added: #{File.basename(file_path)}"
        success_count += 1
      end
    end

    puts "=" * 60
    puts "✅ Media sync complete! #{success_count} new files\n\n"
  end

  def sync_documentation
    relative_paths = Dir.glob("site/documentation/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    return if markdown_files.empty?

    puts "\n📖 Found #{markdown_files.count} markdown files in site/documentation"

    # Handle orphaned docs
    handle_orphaned_documentation(markdown_files)

    puts "=" * 60

    success_count = 0
    error_count = 0

    markdown_files.each do |file_path|
      result = sync_documentation_file(file_path)

      case result
      when :success
        success_count += 1
      when :error
        error_count += 1
      end
    end

    puts "=" * 60
    puts "✅ Documentation sync complete! #{success_count} synced, #{error_count} errors\n\n"
  end

  def sync_products
    relative_paths = Dir.glob("site/products/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    puts "\n🛍️  Found #{markdown_files.count} markdown files in site/products"

    handle_orphaned_products(markdown_files)

    puts "=" * 60

    success_count = 0
    error_count = 0
    error_files = []

    markdown_files.each do |file_path|
      begin
        relative_path = file_path.sub(Rails.root.to_s + "/", "")
        content = File.read(file_path)

        # Parse frontmatter
        if content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
          frontmatter = YAML.safe_load($1, permitted_classes: [Date, Time, Symbol])
          body = $2
        else
          puts "⚠️  Skipping #{relative_path}: No frontmatter found"
          next
        end

        # Find or initialize product
        product = Product.find_by(file_path: relative_path) || Product.new

        # Update attributes
        product.assign_attributes(
          content: body,
          file_path: relative_path,
          metadata: frontmatter || {}
        )

        if product.save
          puts "✓ Synced: #{relative_path}"
          success_count += 1
        else
          puts "✗ Failed: #{relative_path}"
          puts "  Errors: #{product.errors.full_messages.join(', ')}"
          error_count += 1
          error_files << relative_path
        end
      rescue => e
        puts "✗ Error processing #{relative_path}: #{e.message}"
        error_count += 1
        error_files << relative_path
      end
    end

    puts "=" * 60
    puts "✓ Success: #{success_count}"
    puts "✗ Errors: #{error_count}" if error_count > 0
  end

  def handle_orphaned_products(markdown_files)
    relative_paths = markdown_files.map { |path| path.sub(Rails.root.to_s + "/", "") }
    orphaned_products = Product.where.not(file_path: relative_paths)

    if orphaned_products.any?
      puts "\n🗑️  Found #{orphaned_products.count} orphaned products (deleted from filesystem)"
      orphaned_products.each do |product|
        puts "  - Deleting: #{product.file_path}"
        product.destroy
      end
    end
  end

  private

  def handle_orphaned_posts(current_files)
    orphans = Post.where.not(file_path: current_files)

    return unless orphans.any?

    orphans.each do |orphan|
      old_path = orphan.file_path
      old_basename = File.basename(old_path, '.md')

      # Try to find a renamed file by matching content or metadata
      possible_rename = current_files.find do |file_path|
        # Skip if this file already has a database record
        next if Post.exists?(file_path: file_path)

        # Check if the new filename is similar (could be just adding a number prefix)
        new_basename = File.basename(file_path, '.md')

        # Match if the old name is contained in the new name (handles 01-old-name.md)
        new_basename.include?(old_basename) || old_basename.include?(new_basename.sub(/^\d+-/, ''))
      end

      if possible_rename
        puts "🔄 Detected rename: #{File.basename(old_path)} → #{File.basename(possible_rename)}"
        orphan.update(file_path: possible_rename)
      else
        puts "🧹 Removing orphaned post: #{File.basename(old_path)}"
        orphan.destroy
      end
    end
  end

  def handle_orphaned_pages(current_files)
    orphans = Page.where.not(file_path: current_files)

    return unless orphans.any?

    orphans.each do |orphan|
      old_path = orphan.file_path
      old_basename = File.basename(old_path, '.md')

      possible_rename = current_files.find do |file_path|
        next if Page.exists?(file_path: file_path)

        new_basename = File.basename(file_path, '.md')
        new_basename.include?(old_basename) || old_basename.include?(new_basename.sub(/^\d+-/, ''))
      end

      if possible_rename
        puts "🔄 Detected rename: #{File.basename(old_path)} → #{File.basename(possible_rename)}"
        orphan.update(file_path: possible_rename)
      else
        puts "🧹 Removing orphaned page: #{File.basename(old_path)}"
        orphan.destroy
      end
    end
  end

  def handle_orphaned_documentation(current_files)
    orphans = Documentation.where.not(file_path: current_files)

    return unless orphans.any?

    orphans.each do |orphan|
      old_path = orphan.file_path
      old_basename = File.basename(old_path, '.md')

      possible_rename = current_files.find do |file_path|
        next if Documentation.exists?(file_path: file_path)

        new_basename = File.basename(file_path, '.md')
        new_basename.include?(old_basename) || old_basename.include?(new_basename.sub(/^\d+-/, ''))
      end

      if possible_rename
        puts "🔄 Detected rename: #{File.basename(old_path)} → #{File.basename(possible_rename)}"
        orphan.update(file_path: possible_rename)
      else
        puts "🧹 Removing orphaned documentation: #{File.basename(old_path)}"
        orphan.destroy
      end
    end
  end

  def handle_orphaned_media(current_files)
    # Convert to web paths for comparison
    current_web_paths = current_files.map { |f| f.sub('site', '') }

    orphans = Medium.where.not(file_path: current_web_paths)

    return unless orphans.any?

    orphans.each do |orphan|
      puts "🧹 Removing orphaned media: #{File.basename(orphan.file_path)}"
      orphan.destroy
    end
  end

  def self.sync_file(file_path)
    result = if file_path.to_s.include?('/posts/')
      Post.create_or_update_from_file(file_path)
    elsif file_path.to_s.include?('/pages/')
      Page.create_or_update_from_file(file_path)
    elsif file_path.to_s.include?('/products/')
      Product.create_or_update_from_file(file_path)
    end

    if result.is_a?(Symbol) && result == :warning
      puts "  ⚠ Synced with warnings: #{File.basename(file_path)}"
      :warning
    elsif result
      puts "  ✓ Synced: #{File.basename(file_path)}"
      :success
    else
      :error
    end
  rescue => e
    Rails.logger.error "Unexpected error syncing #{file_path}: #{e.message}"
    puts "  ✗ Unexpected error: #{File.basename(file_path)}"
    :error
  end

  def sync_page_file(file_path)
    result = Page.create_or_update_from_file(file_path)

    if result
      puts "  ✓ Synced: #{File.basename(file_path)}"
      :success
    else
      :error
    end
  rescue => e
    Rails.logger.error "Unexpected error syncing #{file_path}: #{e.message}"
    puts "  ✗ Unexpected error: #{File.basename(file_path)}"
    :error
  end

  def sync_documentation_file(file_path)
    result = Documentation.create_or_update_from_file(file_path)

    if result
      puts "  ✓ Synced: #{File.basename(file_path)}"
      :success
    else
      :error
    end
  rescue => e
    Rails.logger.error "Unexpected error syncing #{file_path}: #{e.message}"
    puts "  ✗ Unexpected error: #{File.basename(file_path)}"
    :error
  end

  def sync_defaults
    defaults_path = SiteConfig::DEFAULTS_PATH
    return unless Dir.exist?(defaults_path)

    puts "\n⚙️  Syncing default configurations"
    puts "=" * 60

    Dir.glob(defaults_path.join('*.yml')).each do |file|
      type = File.basename(file, '.yml')
      result = SiteConfig.sync_from_file("defaults/#{type}")

      if result
        puts "  ✓ #{type.capitalize} defaults synced"
      else
        puts "  ✗ #{type.capitalize} defaults sync failed"
      end
    end

    puts "=" * 60
  end

  def sync_site_config
    return unless File.exist?(SiteConfig::SITE_FILE)  # Changed from FILE_PATH

    puts "\n⚙️  Syncing site configuration"
    puts "=" * 60

    result = SiteConfig.sync_from_file('site')  # Added 'site' argument

    if result
      puts "  ✓ Site config synced"
    else
      puts "  ✗ Site config sync failed"
    end

    puts "=" * 60
  end
end
