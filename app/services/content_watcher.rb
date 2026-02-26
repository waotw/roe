class ContentWatcher
  WATCH_PATHS = [ 'content/posts', 'content/pages' ].freeze

  def self.start
    listener = Listen.to(*WATCH_PATHS) do |modified, added, removed|
      handle_changes(modified, added, removed)
    end

    listener.start
    puts "👀 Watching #{WATCH_PATHS.join(', ')} for changes..."

    listener
  end

  private

  def self.handle_changes(modified, added, removed)
    added.each do |file|
      next unless file.end_with?('.md')
      puts "✨ New file detected: #{file}"
      process_file(file)
    end

    modified.each do |file|
      next unless file.end_with?('.md')
      puts "📝 File modified: #{file}"
      process_file(file)
    end

    removed.each do |file|
      next unless file.end_with?('.md')
      puts "🗑️  File removed: #{file}"
      remove_file(file)
    end
  end

  def self.process_file(file)
    if file.include?('content/posts')
      post = Post.create_or_update_from_file(file)
      puts "   Saved: #{post.title}"
    elsif file.include?('content/pages')
      # Future: Page.create_or_update_from_file(file)
      puts "   Pages not yet implemented"
    end
  rescue => e
    puts "   ✗ Error: #{e.message}"
  end

  def self.remove_file(file)
    if file.include?('content/posts')
      Post.remove_by_file_path(file)
      puts "   Removed from database"
    elsif file.include?('content/pages')
      # Future: Page.remove_by_file_path(file)
      puts "   Pages not yet implemented"
    end
  end
end
