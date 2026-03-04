class ContentSync
  def self.sync_all
    new.sync_all
  end

  def sync_all
    sync_posts
    sync_pages
  end

  def sync_posts
    relative_paths = Dir.glob("content/posts/**/*.md")
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    puts "\n📚 Found #{markdown_files.count} markdown files in content/posts"

    # Clean up orphaned records
    orphans = Post.where.not(file_path: markdown_files)
    if orphans.any?
      puts "🧹 Removing #{orphans.count} orphaned post(s) from database"
      orphans.destroy_all
    end

    puts "=" * 60

    success_count = 0
    error_count = 0
    error_files = []
    warning_files = []

    markdown_files.each do |file_path|
      result = result = self.class.sync_file(file_path)

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

  private

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
      :error  # Error already logged by Post/Page model
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
end
