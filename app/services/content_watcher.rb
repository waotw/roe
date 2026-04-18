class ContentWatcher
  WATCH_PATHS = [ 'site/posts', 'site/pages', 'site/documentation', 'site/products', 'site/system', 'site/media' ].freeze

    # Define what file types we process
    ALLOWED_EXTENSIONS = %w[
      md yml
      jpg jpeg png gif webp svg
      mp3 m4a wav ogg flac aac
      mp4 webm ogv mov avi mkv
    ].freeze

    EXTENSION_PATTERN = /\.(#{ALLOWED_EXTENSIONS.join('|')})$/i

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
    puts "\n🔔 File changes detected:"
    puts "  Added: #{added.inspect}"
    puts "  Modified: #{modified.inspect}"
    puts "  Removed: #{removed.inspect}"
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
      next unless file.match?(EXTENSION_PATTERN)
      puts "\n" + "=" * 60
      puts "✨ New file: #{File.basename(file)}"
      puts "=" * 60
      process_file(file)
      puts ""
    end

    modified.each do |file|
      next unless file.match?(EXTENSION_PATTERN)
      puts "\n" + "=" * 60
      puts "📝 Modified: #{File.basename(file)}"
      puts "=" * 60
      process_file(file)
      puts ""
    end

    # Handle remaining removals (not part of renames)
    (removed - potential_renames.keys).each do |file|
      next unless file.match?(EXTENSION_PATTERN)
      puts "\n" + "=" * 60
      puts "🗑️  Removed: #{File.basename(file)}"
      puts "=" * 60
      remove_file(file)
      puts ""
    end

    # After processing all changes, trigger static generation
    if static_generation_enabled?
      trigger_static_generation
    else
      puts "\nℹ️  Static generation disabled (enable in Site Config)"
    end
  end


  def self.static_generation_enabled?
    site_config = SiteConfig.first
    site_config&.config&.dig('static_generation_enabled') == true  # Change to 'config'
  rescue => e
    Rails.logger.debug "Static generation check failed: #{e.message}"
    false
  end

  def self.trigger_static_generation
    puts "\n" + "=" * 60
    puts "🔨 Regenerating static site..."
    puts "=" * 60

    start_time = Time.current

    begin
      generator = StaticGenerator.new
      stats = generator.generate_all

      duration = (Time.current - start_time).round(2)

      if stats[:errors].empty?
        puts "✅ Static site generated successfully in #{duration}s"
        puts "   Posts: #{stats[:posts]}, Pages: #{stats[:pages]}, Collections: #{stats[:collection_pages]}"
      else
        puts "⚠️  Static site generated with #{stats[:errors].count} errors in #{duration}s"
        stats[:errors].first(3).each do |error|
          puts "   - #{error[:type]}: #{error[:message]}"
        end
      end
    rescue => e
      duration = (Time.current - start_time).round(2)
      puts "❌ Static generation failed after #{duration}s: #{e.message}"
      Rails.logger.error "Static generation error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    puts "=" * 60
    puts ""
  end

  def self.process_file(file)
    absolute_file = File.expand_path(file)

    # Handle global configs (site.yml, fonts.yml)
    if absolute_file.include?('site/system/global/')
      filename = File.basename(file, '.yml')
      SiteConfig.sync_from_file(filename)
      puts "\n   ✓ #{filename.capitalize} config reloaded\n"

    # Handle feature configs (members.yml, podcast.yml, store.yml)
    elsif absolute_file.include?('site/system/features/')
      type = File.basename(file, '.yml')
      SiteConfig.sync_from_file("features/#{type}")
      puts "\n   ✓ #{type.capitalize} feature config reloaded\n"

    # Handle default configs (cards.yml, collections.yml)
    elsif absolute_file.include?('site/system/defaults/')
      type = File.basename(file, '.yml')
      SiteConfig.sync_from_file("defaults/#{type}")
      puts "\n   ✓ #{type.capitalize} defaults reloaded\n"

    elsif absolute_file.include?('site/posts')
      result = Post.create_or_update_from_file(absolute_file)

      case result
      when :warning
        puts "\n   ⚠ Saved with warnings: #{File.basename(file)}\n"
      when nil
        # Error already logged
      else
        puts "\n   ✓ Post saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?('site/pages')
      result = Page.create_or_update_from_file(absolute_file)

      if result
        puts "\n   ✓ Page saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?('site/documentation')
      result = Documentation.create_or_update_from_file(absolute_file)

      if result
        puts "\n   ✓ Documentation saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?('site/products')
      result = Product.create_or_update_from_file(absolute_file)

      if result
        puts "\n   ✓ Product saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?('site/media') && absolute_file.match?(/\.(jpg|jpeg|png|gif|webp|svg|mp3|m4a|wav|ogg|flac|aac|mp4|webm|ogv|mov|avi|mkv)$/i)
      # Skip variant files - they shouldn't be tracked in media table
      if absolute_file.include?('/variants/')
        puts "DEBUG: Skipping variant file: #{absolute_file}"
        return
      end

      puts "DEBUG: Processing media file: #{absolute_file}"

      web_path = absolute_file.sub(Rails.root.join('site').to_s, '')
      puts "DEBUG: Web path: #{web_path}"

      if Medium.exists?(file_path: web_path)
        puts "DEBUG: Record already exists, skipping"
      else
        puts "DEBUG: Creating new record..."
        extension = File.extname(absolute_file).delete_prefix('.')
        medium = Medium.create!(
          file_path: web_path,
          media_type: extension,
          uploaded_at: Time.current
        )
        puts "\n   ✓ Media file added: #{File.basename(file)}\n"

        # Queue variant generation for images
        if medium.image? && ImageVariantGenerator.available?
          puts "   🖼️  Queued for variant generation\n"
        end
      end
    end
  end

  def self.detect_renames(added, removed)
    renames = {}

    removed.each do |old_file|
      # Handle markdown files
      if old_file.end_with?('.md')
        old_basename = File.basename(old_file, '.md')

        new_file = added.find do |file|
          next unless file.end_with?('.md')
          new_basename = File.basename(file, '.md')

          new_basename.include?(old_basename) ||
            old_basename.include?(new_basename.sub(/^\d+-/, ''))
        end

        renames[old_file] = new_file if new_file

      # Handle media files (images)
      elsif old_file.match?(/\.(jpg|jpeg|png|gif|webp|svg|mp3|m4a|wav|ogg|flac|aac|mp4|webm|ogv|mov|avi|mkv)$/i)
        old_basename = File.basename(old_file, File.extname(old_file))
        old_ext = File.extname(old_file)

        new_file = added.find do |file|
          next unless file.end_with?(old_ext) # Same extension
          new_basename = File.basename(file, File.extname(file))

          # For media, we want more exact matching
          new_basename.include?(old_basename) || old_basename.include?(new_basename)
        end

        renames[old_file] = new_file if new_file
      end
    end

    renames
  end

  def self.handle_rename(old_path, new_path)
    absolute_old = File.expand_path(old_path)
    absolute_new = File.expand_path(new_path)

    if absolute_old.include?('site/posts')
      post = Post.find_by(file_path: absolute_old)
      if post
        post.update(file_path: absolute_new)
        Post.create_or_update_from_file(absolute_new)
        puts "   ✓ Post renamed in database"
      end
    elsif absolute_old.include?('site/pages')
      page = Page.find_by(file_path: absolute_old)
      if page
        page.update(file_path: absolute_new)
        Page.create_or_update_from_file(absolute_new)
        puts "   ✓ Page renamed in database"
      end
    elsif absolute_old.include?('site/documentation')
      doc = Documentation.find_by(file_path: absolute_old)
      if doc
        doc.update(file_path: absolute_new)
        Documentation.create_or_update_from_file(absolute_new)
        puts "   ✓ Documentation renamed in database"
      end
    elsif absolute_old.include?('site/media')
      # Media files are stored with web paths like "/media/images/file.jpg"
      old_web_path = absolute_old.sub(Rails.root.join('site').to_s, '')
      new_web_path = absolute_new.sub(Rails.root.join('site').to_s, '')

      medium = Medium.find_by(file_path: old_web_path)
      if medium
        medium.update(file_path: new_web_path)
        puts "   ✓ Media file renamed in database"
        puts "   Old: #{old_web_path}"
        puts "   New: #{new_web_path}"
      end
    end
  end

  def self.remove_file(file)
    absolute_file = File.expand_path(file)

    # Handle config files first
    if absolute_file.include?('site/system')
      handle_config_removed(absolute_file)
    elsif absolute_file.include?('site/posts')
      Post.remove_by_file_path(absolute_file)
      puts "   Removed post from database"
    elsif absolute_file.include?('site/pages')
      Page.remove_by_file_path(absolute_file)
      puts "   Removed page from database"
    elsif absolute_file.include?('site/documentation')
      Documentation.remove_by_file_path(absolute_file)
      puts "   Removed documentation from database"
    elsif absolute_file.include?('site/media')
      web_path = absolute_file.sub(Rails.root.join('site').to_s, '')
      Medium.remove_by_file_path(web_path)
      puts "   Removed media file from database"
    end
  end

  def self.handle_config_removed(file_path)
    filename = File.basename(file_path)

    # Handle OLD structure (for backward compatibility during migration)
    if file_path.include?('site/system/') && !file_path.include?('defaults/') && !file_path.include?('global/') && !file_path.include?('features/')
      # Old root-level config (site.yml) - ignore it, should be in global/ now
      puts "   ℹ️  Ignoring old config location: #{filename} (should be in global/ or features/)"
      return
    end

    # Determine config type based on NEW directory structure
    if file_path.include?('system/global')
      handle_global_config_removed(filename, file_path)
    elsif file_path.include?('system/defaults')
      handle_defaults_config_removed(filename, file_path)
    elsif file_path.include?('system/features')
      handle_features_config_removed(filename, file_path)
    else
      puts "   ℹ️  Unknown config file removed: #{filename}"
    end
  end

  def self.handle_global_config_removed(filename, file_path)
    case filename
    when 'site.yml'
      restore_required_config('site', file_path)
    when 'fonts.yml'
      restore_required_config('fonts', file_path)
    else
      puts "   ℹ️  Unknown global config file removed: #{filename}"
    end
  end

  def self.handle_global_config_removed(filename, file_path)
    case filename
    when 'site.yml'
      restore_required_config('site', file_path)
    when 'fonts.yml'
      restore_required_config('fonts', file_path)
    else
      puts "   ℹ️  Unknown global config file removed: #{filename}"
    end
  end

  def self.handle_defaults_config_removed(filename, file_path)
    case filename
    when 'cards.yml'
      restore_required_config('defaults/cards', file_path)
    when 'collections.yml'
      restore_required_config('defaults/collections', file_path)
    else
      puts "   ℹ️  Unknown defaults config file removed: #{filename}"
    end
  end

  def self.handle_features_config_removed(filename, file_path)
    # Features are optional - allow deletion
    case filename
    when 'members.yml', 'podcast.yml', 'store.yml'
      SiteConfig.find_by("file_path LIKE ?", "%#{filename}")&.destroy
      puts "   🗑️  #{filename.gsub('.yml', '').capitalize} feature disabled (file removed)"
    else
      puts "   ℹ️  Unknown feature config file removed: #{filename}"
    end
  end

  def self.restore_required_config(config_type, file_path)
    filename = config_type.split('/').last
    site_config = SiteConfig.find_by("file_path LIKE ?", "%#{filename}.yml")

    if site_config&.config.present?
      # Restore from database backup
      File.write(file_path, YAML.dump(site_config.config))
      puts "   🔄 Restored #{filename}.yml from database (required config)"
    else
      # Generate fresh defaults
      generator = ConfigGenerator.new
      generator.send(:ensure_directories)

      case config_type
      when 'site'
        generator.send(:generate_site_config)
      when 'fonts'
        generator.send(:generate_fonts_config)
      when 'defaults/cards'
        generator.send(:generate_cards_defaults)
      when 'defaults/collections'
        generator.send(:generate_collections_defaults)
      end

      # Sync new file to database
      SiteConfig.sync_from_file(config_type)
      puts "   ✨ Regenerated default #{filename}.yml (required config)"
    end
  end
end
