class ContentWatcher
  WATCH_PATHS = [ 'content/posts', 'content/pages', 'content/documentation' ].freeze

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
    # Check for renames (removed + added happening together)
    potential_renames = detect_renames(added, removed)

    potential_renames.each do |old_path, new_path|
      puts "\n" + "=" * 60
      puts "🔄 Renamed: #{File.basename(old_path)} → #{File.basename(new_path)}"
      puts "=" * 60
      handle_rename(old_path, new_path)
      puts ""
    end

    # Handle remaining additions (not part of renames)
    (added - potential_renames.values).each do |file|
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

    # Handle remaining removals (not part of renames)
    (removed - potential_renames.keys).each do |file|
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

    elsif absolute_file.include?('content/documentation')
      result = Documentation.create_or_update_from_file(absolute_file)

      if result
        puts "\n   ✓ Documentation saved: #{result.title || File.basename(file)}\n"
      end
    end
  end

  def self.detect_renames(added, removed)
    renames = {}

    removed.each do |old_file|
      next unless old_file.end_with?('.md')
      old_basename = File.basename(old_file, '.md')

      # Look for an added file that matches (could be prefixed with numbers)
      new_file = added.find do |file|
        next unless file.end_with?('.md')
        new_basename = File.basename(file, '.md')

        # Match if the old name is contained in the new name
        new_basename.include?(old_basename) ||
          old_basename.include?(new_basename.sub(/^\d+-/, ''))
      end

      if new_file
        renames[old_file] = new_file
      end
    end

    renames
  end

  def self.handle_rename(old_path, new_path)
    absolute_old = File.expand_path(old_path)
    absolute_new = File.expand_path(new_path)

    # Find the record by old path and update to new path
    if absolute_old.include?('content/posts')
      post = Post.find_by(file_path: absolute_old)
      if post
        post.update(file_path: absolute_new)
        # Re-process to update metadata if needed
        Post.create_or_update_from_file(absolute_new)
        puts "   ✓ Post renamed in database"
      end
    elsif absolute_old.include?('content/pages')
      page = Page.find_by(file_path: absolute_old)
      if page
        page.update(file_path: absolute_new)
        Page.create_or_update_from_file(absolute_new)
        puts "   ✓ Page renamed in database"
      end
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
    elsif absolute_file.include?('content/documentation')
      Documentation.remove_by_file_path(absolute_file)
      puts "   Removed documentation from database"
    end
  end
end
