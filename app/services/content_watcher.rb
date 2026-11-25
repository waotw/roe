class ContentWatcher
  WATCH_PATHS = [
    File.join(RoeSitePaths::SITE_PATH, "posts"),
    File.join(RoeSitePaths::SITE_PATH, "pages"),
    File.join(RoeSitePaths::SITE_PATH, "documentation"),
    File.join(RoeSitePaths::SITE_PATH, "products"),
    File.join(RoeSitePaths::SITE_PATH, "system"),
    File.join(RoeSitePaths::SITE_PATH, "media"),
    # These don't sync into DB models — process_file falls through with
    # no work to do — but they DO need to wake the watcher so the
    # trigger_static_generation call at the end of handle_changes fires.
    # Without them, edits to navigation.md or theme CSS don't
    # auto-regenerate the static site. (Content/card templates live under
    # system/templates, already covered by the "system" entry above.)
    File.join(RoeSitePaths::SITE_PATH, "layout"),
    File.join(RoeSitePaths::SITE_PATH, "theme")
  ].freeze

    # What ContentWatcher processes, split by what each half answers.
    #
    # The media half used to be written twice — here, and again as an inline
    # regex in process_file — so the two could disagree about what a media file
    # is. A type in one but not the other is either watched and never recorded,
    # or recorded and never removed when the file is deleted. Derived from one
    # list now, so they can't drift.
    CONTENT_EXTENSIONS = %w[md yml].freeze

    # Keep in step with what the media browser accepts on upload
    # (Admin::MediumController#determine_media_type) and what ContentSync moves.
    # bmp was accepted by both of those and missing here, so a .bmp deleted from
    # disk stayed in the media browser — the bug this list is now shaped to
    # prevent, found while closing the report of it for video.
    MEDIA_EXTENSIONS = %w[
      jpg jpeg png gif webp svg bmp
      mp3 m4a wav ogg flac aac
      mp4 webm ogv mov avi mkv
    ].freeze

    ALLOWED_EXTENSIONS = (CONTENT_EXTENSIONS + MEDIA_EXTENSIONS).freeze

    EXTENSION_PATTERN = /\.(#{ALLOWED_EXTENSIONS.join('|')})$/i
    MEDIA_PATTERN     = /\.(#{MEDIA_EXTENSIONS.join('|')})$/i

  def self.start
    # Listen calls realpath on every watched dir at startup, so a single
    # missing path (a site that never created site/theme, or a directory
    # that moved) raises ENOENT and takes the whole watcher — and all
    # content auto-sync — down with it. Watch only the dirs that exist;
    # a missing optional dir simply isn't watched.
    paths = WATCH_PATHS.select { |p| Dir.exist?(p) }
    if (missing = WATCH_PATHS - paths).any?
      puts "⚠️  ContentWatcher skipping missing paths: #{missing.join(', ')}"
    end

    # A start loads every file again (ContentSync), so earlier errors are
    # settled; anything still wrong is recorded again when it changes.
    write_errors({})
    # Anything the listen gem catches itself goes to the Rails log too, not
    # only to the background log: its warnings and errors, not its chatter
    # (ListenLog).
    Listen.logger = ListenLog.new

    listener = Listen.to(*paths, ignore: /\/variants\//) do |modified, added, removed|
      handle_changes(modified, added, removed)
    end

    listener.start
    mark_seen
    puts "👀 Watching #{paths.join(', ')} for changes (ignoring variants)..."

    listener
  end

  # An empty file whose date says when the watcher last heard anything: set
  # when it starts and on every change it's told about. `roe status`
  # (bin/roe-watch-check) compares the content files against it — a file
  # changed after this date, and not just now, is one the watcher missed.
  # The watcher can stop hearing changes without stopping (a disk remounted
  # under it, for one), so this is the only reliable sign. Lives in tmp/,
  # which isn't watched, so touching it can't wake the watcher.
  SEEN_FILE = Rails.root.join("tmp", Rails.env.test? ? "content_watcher-test.seen" : "content_watcher.seen")

  def self.mark_seen
    FileUtils.mkdir_p(File.dirname(SEEN_FILE))
    FileUtils.touch(SEEN_FILE)
  rescue SystemCallError => e
    Rails.logger.warn("ContentWatcher couldn't update #{SEEN_FILE}: #{e.message}")
  end

  private

  def self.handle_changes(modified, added, removed)
    # First, before anything that can fail: hearing the change is what counts.
    mark_seen
    puts "\n🔔 File changes detected:"
    puts "  Added: #{added.inspect}"
    puts "  Modified: #{modified.inspect}"
    puts "  Removed: #{removed.inspect}"
    # A file both removed and added in one batch is still there: an editor
    # that saves by replacing the file. It changed; nothing moved.
    replaced = removed & added
    if replaced.any?
      removed -= replaced
      added -= replaced
      modified |= replaced
    end

    # Check for renames (removed + added happening together)
    potential_renames = detect_renames(added, removed)

    potential_renames.each do |old_path, new_path|
      puts "\n" + "=" * 60
      puts "🔄 Renamed: #{File.basename(old_path)} → #{File.basename(new_path)}"
      puts "=" * 60
      handling(new_path) { handle_rename(old_path, new_path) }
      puts ""
    end

    # Handle remaining additions (not part of renames)
    (added - potential_renames.values).each do |file|
      next unless file.match?(EXTENSION_PATTERN)
      puts "\n" + "=" * 60
      puts "✨ New file: #{File.basename(file)}"
      puts "=" * 60
      handling(file) { process_file(file) }
      puts ""
    end

    modified.each do |file|
      next unless file.match?(EXTENSION_PATTERN)
      puts "\n" + "=" * 60
      puts "📝 Modified: #{File.basename(file)}"
      puts "=" * 60
      handling(file) { process_file(file) }
      puts ""
    end

    # Handle remaining removals (not part of renames)
    (removed - potential_renames.keys).each do |file|
      next unless file.match?(EXTENSION_PATTERN)
      puts "\n" + "=" * 60
      puts "🗑️  Removed: #{File.basename(file)}"
      puts "=" * 60
      handling(file) { remove_file(file) }
      puts ""
    end

    # After processing all changes, trigger static generation
    if static_generation_enabled?
      trigger_static_generation
    else
      puts "\nℹ️  Static generation disabled (enable in Site Config)"
    end

    # Tell SiteSync something in /site changed — this side's
    # drift caches are now stale, and the peer's view of us is
    # also stale. Bust the local caches so the admin banner
    # reflects the new state on the next render, and schedule a
    # peer ping so the other side learns within seconds (instead
    # of waiting up to an hour for the recurring exchange).
    notify_site_sync if (modified + added + removed).any?

    # Links and media files may have changed: check the site's links again
    # (in the background, once the batch settles).
    LinkCheck.request("change") if (modified + added + removed).any? { |file| link_check_file?(file) }
  end

  # Content, a layout, or an original media file. Variants come and go with
  # their originals, and config and theme files hold no links the check reads.
  def self.link_check_file?(file)
    path = relative_site_path(file).to_s
    return false if path.include?("/variants/")

    path.match?(%r{\A(posts|pages|products|documentation|media|layout)/})
  end

  def self.notify_site_sync
    Rails.cache.delete("site_sync:current_fingerprint")
    SiteSync::Checker.clear_cache

    # perform_later doesn't block the watcher thread; the job runs
    # in the Solid Queue worker and updates peer_state in the
    # cache when it returns.
    SiteSyncExchangeJob.perform_later if SiteSync::Exchange.can_call_peer?
  rescue => e
    Rails.logger.warn "[ContentWatcher] notify_site_sync failed: #{e.class} #{e.message}"
  end


  def self.static_generation_enabled?
    site_config = SiteConfig.first
    site_config&.config&.dig("static_generation_enabled") == true  # Change to 'config'
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
    # Normalize through realpath so models receive the same path
    # form they store (resolves the /rails/site → /data/site symlink
    # on prod). The media branch below ALSO does this normalization
    # explicitly via File.realpath; this top-level call covers
    # posts/pages/documentation/products.
    absolute_file = RoeSitePaths.normalize(file)

    # Handle global configs (site.yml, fonts.yml)
    if absolute_file.include?("site/system/global/")
      filename = File.basename(file, ".yml")
      SiteConfig.sync_from_file(filename)
      puts "\n   ✓ #{filename.capitalize} config reloaded\n"

    # Handle feature configs (members.yml, podcast.yml, store.yml)
    elsif absolute_file.include?("site/system/features/")
      type = File.basename(file, ".yml")
      SiteConfig.sync_from_file("features/#{type}")
      puts "\n   ✓ #{type.capitalize} feature config reloaded\n"

    # Handle default configs (cards.yml, collections.yml)
    elsif absolute_file.include?("site/system/defaults/")
      type = File.basename(file, ".yml")
      SiteConfig.sync_from_file("defaults/#{type}")
      puts "\n   ✓ #{type.capitalize} defaults reloaded\n"

    # Handle integration configs (stripe.yml, postmark.yml, snipcart.yml)
    elsif absolute_file.include?("site/system/integrations/")
      type = File.basename(file, ".yml")
      SiteConfig.sync_from_file("integrations/#{type}")
      puts "\n   ✓ #{type.capitalize} integration config reloaded\n"

    elsif absolute_file.include?("site/posts")
      result = following_links(Post, absolute_file) { Post.create_or_update_from_file(absolute_file) }

      case result
      when :warning
        puts "\n   ⚠ Saved with warnings: #{File.basename(file)}\n"
      when nil
        # Error already logged
      else
        puts "\n   ✓ Post saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?("site/pages")
      result = following_links(Page, absolute_file) { Page.create_or_update_from_file(absolute_file) }

      if result
        puts "\n   ✓ Page saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?("site/documentation")
      result = following_links(Documentation, absolute_file) { Documentation.create_or_update_from_file(absolute_file) }

      if result
        puts "\n   ✓ Documentation saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?("site/products")
      result = following_links(Product, absolute_file) { Product.create_or_update_from_file(absolute_file) }

      if result
        puts "\n   ✓ Product saved: #{result.title || File.basename(file)}\n"
      end

    elsif absolute_file.include?("site/media") && absolute_file.match?(MEDIA_PATTERN)
      # Skip variant files - they shouldn't be tracked in media table
      if absolute_file.include?("/variants/")
        puts "DEBUG: Skipping variant file: #{absolute_file}"
        return
      end

      puts "DEBUG: Processing media file: #{absolute_file}"

      # Handle symlinks - resolve to real path before substitution
      # In production, /rails/site is a symlink to /data/site
      web_path = media_web_path(absolute_file)
      puts "DEBUG: Web path: #{web_path}"

      if Medium.exists?(file_path: web_path)
        puts "DEBUG: Record already exists, skipping"
      else
        puts "DEBUG: Creating new record..."
        extension = File.extname(absolute_file).delete_prefix(".")
        # create_or_find_by: an admin upload creates its own record right
        # after renaming the file into place, so the two can race.
        medium = Medium.create_or_find_by!(file_path: web_path) do |m|
          m.media_type = extension
          m.uploaded_at = Time.current
        end
        puts "\n   ✓ Media file added: #{File.basename(file)}\n"

        # Queue variant generation for images
        if medium.image? && ImageVariantGenerator.available?
          puts "   🖼️  Queued for variant generation\n"
        end
      end
    end
  end

  # The listen gem's warnings and errors, passed to the Rails log. Its debug
  # and info lines are dropped: at debug level (every local install) it
  # writes "(silenced): <path>" for each ignored file, and Roe writes image
  # variants by the thousand on a first start or an import.
  class ListenLog < ::Logger
    def initialize
      super(nil, level: ::Logger::WARN)
    end

    def add(severity, message = nil, progname = nil)
      return true if severity.to_i < level

      message ||= block_given? ? yield : progname
      Rails.logger.add(severity, "[listen] #{message}")
    end
  end

  def self.detect_renames(added, removed)
    renames = content_renames(added, removed)

    removed.each do |old_file|
      # Media files. Third copy of the same list until now — a type missing
      # here isn't seen as a rename, so it reads as a delete plus an add and
      # the record is destroyed and recreated instead of moved.
      if old_file.match?(MEDIA_PATTERN)
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

  # Removed content files that were renamed, by their records (RenameMatch).
  # Content files that share a name aren't matched by name: `music.md` →
  # `music-2.md` could as well be a new post.
  def self.content_renames(added, removed)
    records = removed.select { |file| file.end_with?(".md") }.filter_map do |old_file|
      record = [ Post, Page, Documentation, Product ].lazy.map { |model| content_record(model, old_file) }.find(&:itself)
      [ old_file, record ] if record
    end.to_h
    return {} if records.empty?

    renames, unsure = RenameMatch.pairs(records, added.select { |file| file.end_with?(".md") })
    unsure.each do |old_file|
      puts "   ⚠️  #{File.basename(old_file)} may have been renamed, but more than one file matches it; treating it as removed"
    end
    renames
  end

  # A media file's address in the media table: "/media/video/a.mp4". The
  # site folder is resolved (production's /rails/site is a symlink to
  # /data/site) and so is the file's folder, but never the file itself: a
  # removed or renamed-away file is gone, and File.realpath on it raised
  # ENOENT — so a deleted video's record was never removed.
  def self.media_web_path(absolute_file)
    site = File.realpath(RoeSitePaths::SITE_PATH.to_s)
    dir = File.dirname(absolute_file)
    path = File.directory?(dir) ? File.join(File.realpath(dir), File.basename(absolute_file)) : File.expand_path(absolute_file)
    [ site, File.expand_path(RoeSitePaths::SITE_PATH.to_s) ].each do |root|
      return path.delete_prefix(root) if path.start_with?("#{root}/")
    end
    path
  end

  # One file's change, on its own: an error loading it is logged and
  # recorded for `roe status` (bin/roe-watch-check), and the other files in
  # the same batch still load. Before, the first error ended the batch, and
  # the listen gem wrote it only to the background log.
  ERRORS_FILE = Rails.root.join("tmp", Rails.env.test? ? "content_watcher-test.errors" : "content_watcher.errors")

  def self.handling(file)
    yield
    clear_error(file)
  rescue StandardError => e
    Rails.logger.error("[ContentWatcher] couldn't load #{file}: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(5).join("\n")}")
    puts "   ✗ Couldn't load #{File.basename(file)}: #{e.class}: #{e.message}"
    record_error(file, e)
  end

  def self.watcher_errors
    File.file?(ERRORS_FILE) ? JSON.parse(File.read(ERRORS_FILE)) : {}
  rescue JSON::ParserError, SystemCallError
    {}
  end

  def self.record_error(file, error)
    errors = watcher_errors
    errors[relative_site_path(file)] = { "error" => "#{error.class}: #{error.message}".truncate(300), "at" => Time.current.to_i }
    write_errors(errors)
  end

  def self.clear_error(file)
    errors = watcher_errors
    write_errors(errors) if errors.delete(relative_site_path(file))
  end

  def self.write_errors(errors)
    if errors.empty?
      FileUtils.rm_f(ERRORS_FILE)
    else
      FileUtils.mkdir_p(File.dirname(ERRORS_FILE))
      File.write(ERRORS_FILE, JSON.generate(errors.sort_by { |_, v| -v["at"] }.first(20).to_h))
    end
  rescue SystemCallError => e
    Rails.logger.warn("ContentWatcher couldn't write #{ERRORS_FILE}: #{e.message}")
  end

  def self.relative_site_path(file)
    path = File.expand_path(file.to_s)
    [ File.expand_path(RoeSitePaths::SITE_PATH.to_s), (File.realpath(RoeSitePaths::SITE_PATH.to_s) rescue nil) ].compact.each do |root|
      return path.delete_prefix("#{root}/") if path.start_with?("#{root}/")
    end
    path
  end

  def self.handle_rename(old_path, new_path)
    # Old path no longer exists (normalize falls back to expand_path).
    # New path exists, so it'll resolve through realpath cleanly.
    absolute_old = RoeSitePaths.normalize(old_path)
    absolute_new = RoeSitePaths.normalize(new_path)

    if absolute_old.include?("site/posts")
      post = Post.find_by(file_path: absolute_old)
      if post
        following_links(Post, absolute_new, old_file: absolute_old) do
          post.update(file_path: absolute_new)
          Post.create_or_update_from_file(absolute_new)
        end
        puts "   ✓ Post renamed in database"
      end
    elsif absolute_old.include?("site/pages")
      page = Page.find_by(file_path: absolute_old)
      if page
        following_links(Page, absolute_new, old_file: absolute_old) do
          page.update(file_path: absolute_new)
          Page.create_or_update_from_file(absolute_new)
        end
        puts "   ✓ Page renamed in database"
      end
    elsif absolute_old.include?("site/documentation")
      doc = Documentation.find_by(file_path: absolute_old)
      if doc
        following_links(Documentation, absolute_new, old_file: absolute_old) do
          doc.update(file_path: absolute_new)
          Documentation.create_or_update_from_file(absolute_new)
        end
        puts "   ✓ Documentation renamed in database"
      end
    elsif absolute_old.include?("site/products")
      # Products keep their path relative to site/. Without this branch a
      # product renamed outside Roe was never picked up at its new name.
      product = Product.find_by(file_path: relative_site_path(absolute_old))
      if product
        following_links(Product, absolute_new, old_file: absolute_old) do
          product.update(file_path: relative_site_path(absolute_new))
          Product.create_or_update_from_file(absolute_new)
        end
        puts "   ✓ Product renamed in database"
      end
    elsif absolute_old.include?("site/media")
      # Media files are stored with web paths like "/media/images/file.jpg"
      # Handle symlinks - resolve to real path before substitution
      old_web_path = media_web_path(absolute_old)
      new_web_path = media_web_path(absolute_new)

      medium = Medium.find_by(file_path: old_web_path)
      if medium
        medium.update(file_path: new_web_path)
        puts "   ✓ Media file renamed in database"
        puts "   Old: #{old_web_path}"
        puts "   New: #{new_web_path}"
      end
    end
  end

  # A file changed or renamed outside Roe: once its record is updated, the
  # site's own links to it follow its new file name and address
  # (InternalLinkRewriter), as they do after a save or rename in the admin.
  # The file itself is left alone. A failure here never stops the load.
  def self.following_links(model, absolute_file, old_file: nil)
    before = content_record(model, old_file || absolute_file)
    source = before && InternalLinkRewriter.source_for(before)
    result = yield
    after = source && content_record(model, absolute_file)
    if after
      begin
        count = InternalLinkRewriter.follow(source, after, except: absolute_file)
        puts "   🔗 Updated #{count} #{'link'.pluralize(count)} to it" if count.positive?
      rescue StandardError => e
        Rails.logger.error("[ContentWatcher] links to #{absolute_file}: #{e.class}: #{e.message}")
      end
    end
    result
  end

  def self.content_record(model, absolute_file)
    path = model == Product ? relative_site_path(absolute_file) : RoeSitePaths.normalize(absolute_file)
    model.find_by(file_path: path)
  end

  def self.remove_file(file)
    # File is gone — normalize falls back to expand_path internally
    # since realpath would raise ENOENT on a missing file.
    absolute_file = RoeSitePaths.normalize(file)

    # Handle config files first
    if absolute_file.include?("site/system")
      handle_config_removed(absolute_file)
    elsif absolute_file.include?("site/posts")
      Post.remove_by_file_path(absolute_file)
      puts "   Removed post from database"
    elsif absolute_file.include?("site/pages")
      Page.remove_by_file_path(absolute_file)
      puts "   Removed page from database"
    elsif absolute_file.include?("site/documentation")
      Documentation.remove_by_file_path(absolute_file)
      puts "   Removed documentation from database"
    elsif absolute_file.include?("site/media")
      Medium.remove_by_file_path(media_web_path(absolute_file))
      puts "   Removed media file from database"
    end
  end

  def self.handle_config_removed(file_path)
    filename = File.basename(file_path)

    # Handle OLD structure (for backward compatibility during migration)
    if file_path.include?("site/system/") && !file_path.include?("defaults/") && !file_path.include?("global/") && !file_path.include?("features/")
      # Old root-level config (site.yml) - ignore it, should be in global/ now
      puts "   ℹ️  Ignoring old config location: #{filename} (should be in global/ or features/)"
      return
    end

    # Determine config type based on NEW directory structure
    if file_path.include?("system/global")
      handle_global_config_removed(filename, file_path)
    elsif file_path.include?("system/defaults")
      handle_defaults_config_removed(filename, file_path)
    elsif file_path.include?("system/features")
      handle_features_config_removed(filename, file_path)
    else
      puts "   ℹ️  Unknown config file removed: #{filename}"
    end
  end

  def self.handle_global_config_removed(filename, file_path)
    case filename
    when "site.yml"
      restore_required_config("site", file_path)
    when "fonts.yml"
      restore_required_config("fonts", file_path)
    else
      puts "   ℹ️  Unknown global config file removed: #{filename}"
    end
  end

  def self.handle_defaults_config_removed(filename, file_path)
    case filename
    when "cards.yml"
      restore_required_config("defaults/cards", file_path)
    when "collections.yml"
      restore_required_config("defaults/collections", file_path)
    else
      puts "   ℹ️  Unknown defaults config file removed: #{filename}"
    end
  end

  def self.handle_features_config_removed(filename, file_path)
    # Features are optional - allow deletion
    case filename
    when "members.yml", "podcast.yml", "store.yml"
      SiteConfig.find_by("file_path LIKE ?", "%#{filename}")&.destroy
      puts "   🗑️  #{filename.gsub('.yml', '').capitalize} feature disabled (file removed)"
    else
      puts "   ℹ️  Unknown feature config file removed: #{filename}"
    end
  end

  def self.restore_required_config(config_type, file_path)
    filename = config_type.split("/").last
    site_config = SiteConfig.find_by("file_path LIKE ?", "%#{filename}.yml")

    if site_config&.config.present?
      # Restore from database backup
      File.write(file_path, YAML.dump(site_config.config))
      puts "   🔄 Restored #{filename}.yml from database (required config)"
    else
      # Generate fresh defaults. ConfigGenerator.generate_all walks the
      # minimum kit via SiteTemplates::Loader, which skips any file
      # that already exists — so this restores only the missing file
      # (this one) without touching the rest of /site.
      ConfigGenerator.new.generate_all

      # Sync new file to database
      SiteConfig.sync_from_file(config_type)
      puts "   ✨ Regenerated default #{filename}.yml (required config)"
    end
  end
end
