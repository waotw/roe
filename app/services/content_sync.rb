class ContentSync
  def self.sync_all
    new.sync_all
  end

  def sync_all
    sync_site_config
    sync_posts
    sync_pages
    sync_documentation
  end

  def sync_posts
    relative_paths = Dir.glob("content/posts/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    puts "\n📚 Found #{markdown_files.count} markdown files in content/posts"

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
    relative_paths = Dir.glob("content/pages/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    return if markdown_files.empty?

    puts "\n📄 Found #{markdown_files.count} markdown files in content/pages"

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

  def sync_documentation
    relative_paths = Dir.glob("content/documentation/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    return if markdown_files.empty?

    puts "\n📖 Found #{markdown_files.count} markdown files in content/documentation"

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

  def self.sync_file(file_path)
    result = if file_path.to_s.include?('/posts/')
      Post.create_or_update_from_file(file_path)
    elsif file_path.to_s.include?('/pages/')
      Page.create_or_update_from_file(file_path)
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

  def sync_site_config
    return unless File.exist?(SiteConfig::FILE_PATH)

    puts "\n⚙️  Syncing site configuration"
    puts "=" * 60

    result = SiteConfig.sync_from_file

    if result
      puts "  ✓ Site config synced"
    else
      puts "  ✗ Site config sync failed"
    end

    puts "=" * 60
  end
end
