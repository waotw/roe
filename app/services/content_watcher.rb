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
      puts "\n" + "=" * 60
      puts "✨ New file: #{File.basename(file)}"
      puts "=" * 60
      process_file(file)
      puts ""
    end

    modified.each do |file|
      next unless file.end_with?('.md')
      puts "\n" + "=" * 60
      puts "📝 Modified: #{File.basename(file)}"
      puts "=" * 60
      process_file(file)
      puts ""
    end

    removed.each do |file|
      next unless file.end_with?('.md')
      puts "\n" + "=" * 60
      puts "🗑️  Removed: #{File.basename(file)}"
      puts "=" * 60
      remove_file(file)
      puts ""
    end
  end

  def self.process_file(file)
    absolute_file = File.expand_path(file)

    if absolute_file.include?('content/posts')
      result = Post.create_or_update_from_file(absolute_file)

      case result
      when :warning
        puts "\n   ⚠ Saved with warnings: #{File.basename(file)}\n"
      when nil
        # Error already logged
      else
        puts "\n   ✓ Post saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?('content/pages')
      result = Page.create_or_update_from_file(absolute_file)

      if result
        puts "\n   ✓ Page saved: #{result.title || File.basename(file)}\n"
      end
      # Errors already logged
    end
  end

  def self.remove_file(file)
    absolute_file = File.expand_path(file)

    if absolute_file.include?('content/posts')
      Post.remove_by_file_path(absolute_file)
      puts "   Removed post from database"
    elsif absolute_file.include?('content/pages')
      Page.remove_by_file_path(absolute_file)
      puts "   Removed page from database"
    end
  end
end
