class ContentSync
  def self.sync_all
    new.sync_all
  end

  def sync_all
    sync_posts
    # Later: sync_pages when you build that feature
  end

  def sync_posts
    # Get relative paths from glob
    relative_paths = Dir.glob("content/posts/**/*.md")

    # Convert to absolute paths
    markdown_files = relative_paths.map { |path| File.expand_path(path) }

    puts "📚 Found #{markdown_files.count} markdown files in content/posts"

    markdown_files.each do |file_path|
      sync_file(file_path)
    end

    puts "✅ Initial sync complete!"
  end

  private

  def sync_file(file_path)
    Post.create_or_update_from_file(file_path)
    puts "  ✓ Synced: #{File.basename(file_path)}"
  rescue => e
    puts "  ✗ Error syncing #{file_path}: #{e.message}"
  end
end
