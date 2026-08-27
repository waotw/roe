class ContentSync
  def self.sync_all
    new.sync_all
  end

  def sync_all
    sync_configs
    sync_posts
    sync_pages
    sync_documentation
    sync_media
    sync_products
    prune_variant_cache
  end

  # Reconcile the image-variant cache against reality after content +
  # media have synced: unused images drop to their baseline, in-use ones
  # keep the full ladder, orphans are removed. Safe (variants regenerate),
  # so it runs on every sync in every env — this is how manual file drops
  # and sync-in-either-direction get their variant cache tidied without a
  # manual step. Skipped under test to avoid deleting fixtures' variants;
  # prune_all! is exercised directly by the generator spec.
  def prune_variant_cache
    return if Rails.env.test?

    ImageVariantGenerator.prune_all!
  rescue => e
    Rails.logger.warn "[ContentSync] variant prune skipped: #{e.class} #{e.message}"
  end

  def sync_posts
    relative_paths = Dir.glob(File.join(RoeSitePaths::SITE_POSTS_PATH, "**", "*.md"))
    # RoeSitePaths.normalize resolves symlinks (notably /rails/site →
    # /data/site on prod) so the file_path values we hand to model
    # lookups match what the models stored on previous syncs. Without
    # this, every sync after a file change would create a duplicate.
    markdown_files = relative_paths.map { |path| RoeSitePaths.normalize(path) }

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
    relative_paths = Dir.glob(File.join(RoeSitePaths::SITE_PAGES_PATH, "**", "*.md"))
    # RoeSitePaths.normalize resolves symlinks (notably /rails/site →
    # /data/site on prod) so the file_path values we hand to model
    # lookups match what the models stored on previous syncs. Without
    # this, every sync after a file change would create a duplicate.
    markdown_files = relative_paths.map { |path| RoeSitePaths.normalize(path) }

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

  # File extension → canonical media_type bucket. Mirrors the case in
  # Medium#normalize_media_type so the insert_all path below can produce
  # the same DB rows that single create! would, while skipping the per-
  # record before_save callback (insert_all is a single SQL statement
  # and bypasses AR callbacks by design).
  MEDIA_TYPE_BY_EXTENSION = {
    "jpg" => "images", "jpeg" => "images", "png" => "images", "gif" => "images",
    "webp" => "images", "svg" => "images", "bmp" => "images",
    "heic" => "images", "heif" => "images",
    "woff" => "fonts", "woff2" => "fonts", "ttf" => "fonts", "otf" => "fonts",
    "mp3" => "audio", "m4a" => "audio", "wav" => "audio", "ogg" => "audio",
    "flac" => "audio", "aac" => "audio",
    "mp4" => "video", "webm" => "video", "ogv" => "video", "mov" => "video",
    "avi" => "video", "mkv" => "video"
  }.freeze

  MEDIA_INSERT_BATCH = 200

  def sync_media
    # Sync all media types (images, audio, video) - EXCLUDE variants folder
    media_files = Dir.glob(File.join(RoeSitePaths::SITE_MEDIA_PATH, "**", "*.{jpg,jpeg,png,gif,webp,svg,bmp,mp3,m4a,wav,ogg,flac,aac,mp4,webm,ogv,mov,avi,mkv}"))
                     .reject { |path| path.include?("/variants/") }

    puts "\n🎬 Found #{media_files.count} media files"

    # Handle orphaned media
    handle_orphaned_media(media_files)

    puts "=" * 60

    # Pre-load existing paths in one query, then build a single bulk
    # INSERT per chunk. Previously this loop did N exists? queries + M
    # individual Medium.create! calls, each in its own transaction.
    # Against SQLite that's M write transactions contending with the
    # web process, SolidQueue (SOLID_QUEUE_IN_PUMA), and SolidCache. On
    # a fresh production boot that pattern surfaces as runs of
    # "cannot rollback - no transaction is active" — the original busy
    # error is swallowed and Rails finds the transaction already gone
    # by the time it tries to wind down. insert_all is one statement
    # per chunk, atomic, no per-record transaction loop.
    existing_paths = Medium.pluck(:file_path).to_set
    real_site_path = File.realpath(RoeSitePaths::SITE_PATH.to_s)
    now = Time.current

    new_records = []
    image_paths_for_queue = []

    media_files.each do |file_path|
      web_path = File.realpath(file_path).sub(real_site_path, "")
      next if existing_paths.include?(web_path)

      ext       = File.extname(file_path).delete(".").downcase
      canonical = MEDIA_TYPE_BY_EXTENSION[ext] || ext

      new_records << {
        file_path:   web_path,
        media_type:  canonical,
        uploaded_at: File.mtime(file_path),
        created_at:  now,
        updated_at:  now
      }
      image_paths_for_queue << web_path if canonical == "images"
    rescue => e
      Rails.logger.error "[ContentSync] Failed to inspect #{file_path}: #{e.message}"
      puts "  ✗ Error: #{File.basename(file_path)} - #{e.message}"
    end

    inserted = 0
    new_records.each_slice(MEDIA_INSERT_BATCH) do |batch|
      Medium.insert_all(batch)
      inserted += batch.size
    rescue => e
      Rails.logger.error "[ContentSync] Bulk insert failed for batch of #{batch.size}: #{e.class} #{e.message}"
      puts "  ✗ Bulk insert error: #{e.message}"
    end

    puts "  ✓ Added: #{inserted} new media files" if inserted.positive?

    # Only the cheap baseline preview (mirrors Medium#after_create — bulk
    # insert_all skips that callback, so we queue here instead). Runs in
    # every env: ContentSync is the chokepoint every new image funnels
    # through (upload, manual drop, sync in either direction, boot), so
    # this is what warms the baseline on prod too. The rest of the ladder
    # still builds on-demand from the renderer.
    if image_paths_for_queue.any?
      image_count = 0
      image_paths_for_queue.each do |web_path|
        image_count += 1 if ImageVariantGenerator.queue_baseline!(web_path)
      end
      puts "🖼️  Queued #{image_count} images for baseline variant" if image_count.positive?
    end

    puts "=" * 60
    puts "✅ Media sync complete!"
    puts ""
  end

  def sync_documentation
    relative_paths = Dir.glob(File.join(RoeSitePaths::SITE_DOCUMENTATION_PATH, "**", "*.md"))
    # RoeSitePaths.normalize resolves symlinks (notably /rails/site →
    # /data/site on prod) so the file_path values we hand to model
    # lookups match what the models stored on previous syncs. Without
    # this, every sync after a file change would create a duplicate.
    markdown_files = relative_paths.map { |path| RoeSitePaths.normalize(path) }

    # Roe ships its own docs under documentation/roe. A site doesn't need them
    # in its DB — and a production site definitely doesn't — unless it opts in
    # via search.roe_docs, the same gate search and the static build use. Skip
    # syncing them, and drop any left over from a previous opt-in so the index
    # stays in step with what's searchable/publishable.
    unless Documentation.include_roe_docs?
      roe_prefix = File.join(Documentation.normalized_documentation_path, "roe", "")
      markdown_files = markdown_files.reject { |path| path.start_with?(roe_prefix) }
      purge_roe_documentation
    end

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
    relative_paths = Dir.glob(File.join(RoeSitePaths::SITE_PRODUCTS_PATH, "**", "*.md"))
    # RoeSitePaths.normalize resolves symlinks (notably /rails/site →
    # /data/site on prod) so the file_path values we hand to model
    # lookups match what the models stored on previous syncs. Without
    # this, every sync after a file change would create a duplicate.
    markdown_files = relative_paths.map { |path| RoeSitePaths.normalize(path) }

    puts "\n🛍️  Found #{markdown_files.count} markdown files in site/products"

    handle_orphaned_products(markdown_files)

    puts "=" * 60

    success_count = 0
    error_count = 0
    error_files = []

    real_site_path = File.realpath(RoeSitePaths::SITE_PATH.to_s)
    markdown_files.each do |file_path|
      begin
        relative_path = File.realpath(file_path).sub(real_site_path + "/", "")
        content = File.read(file_path)

        # Parse frontmatter
        if content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
          frontmatter = YAML.safe_load($1, permitted_classes: [ Date, Time, Symbol ])
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
    real_site_path = File.realpath(RoeSitePaths::SITE_PATH.to_s)
    relative_paths = markdown_files.map { |path| File.realpath(path).sub(real_site_path + "/", "") }
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
      old_basename = File.basename(old_path, ".md")

      # Try to find a renamed file by matching content or metadata
      possible_rename = current_files.find do |file_path|
        # Skip if this file already has a database record
        next if Post.exists?(file_path: file_path)

        # Check if the new filename is similar (could be just adding a number prefix)
        new_basename = File.basename(file_path, ".md")

        # Match if the old name is contained in the new name (handles 01-old-name.md)
        new_basename.include?(old_basename) || old_basename.include?(new_basename.sub(/^\d+-/, ""))
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
      old_basename = File.basename(old_path, ".md")

      possible_rename = current_files.find do |file_path|
        next if Page.exists?(file_path: file_path)

        new_basename = File.basename(file_path, ".md")
        new_basename.include?(old_basename) || old_basename.include?(new_basename.sub(/^\d+-/, ""))
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

  # Remove Roe docs (documentation/roe) previously synced under an opt-in.
  # They're filtered out of the glob when search.roe_docs is off, so they'd
  # never be re-seen to orphan; drop them explicitly instead (and precisely,
  # rather than letting the fuzzy orphan-rename detector repoint them onto a
  # user's doc of the same basename).
  def purge_roe_documentation
    roe_docs = Documentation.in_directory("roe")
    return unless roe_docs.exists?

    puts "🧹 Roe docs disabled (search.roe_docs) — removing #{roe_docs.count} from index"
    roe_docs.destroy_all
  end

  def handle_orphaned_documentation(current_files)
    orphans = Documentation.where.not(file_path: current_files)

    return unless orphans.any?

    orphans.each do |orphan|
      old_path = orphan.file_path
      old_basename = File.basename(old_path, ".md")

      possible_rename = current_files.find do |file_path|
        next if Documentation.exists?(file_path: file_path)

        new_basename = File.basename(file_path, ".md")
        new_basename.include?(old_basename) || old_basename.include?(new_basename.sub(/^\d+-/, ""))
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
    # Handle symlinks - resolve to real path before substitution
    real_site_path = File.realpath(RoeSitePaths::SITE_PATH.to_s)
    current_web_paths = current_files.map { |f| File.realpath(f).sub(real_site_path, "") }

    orphans = Medium.where.not(file_path: current_web_paths)

    return unless orphans.any?

    orphans.each do |orphan|
      puts "🧹 Removing orphaned media: #{File.basename(orphan.file_path)}"
      orphan.destroy
    end
  end

  def self.sync_file(file_path)
    result = if file_path.to_s.include?("/posts/")
      Post.create_or_update_from_file(file_path)
    elsif file_path.to_s.include?("/pages/")
      Page.create_or_update_from_file(file_path)
    elsif file_path.to_s.include?("/products/")
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

  # Rebuild every database-backed config from the files.
  #
  # This used to sync site.yml and the defaults only, which left every
  # features/*.yml row holding pre-sync values after a transfer — the files on
  # disk said one thing and the running app read another, until a restart.
  #
  # It has to happen before content syncs, not just eventually: Product's
  # after_save appends its category to store.yml, and with a stale store config
  # in the database it rewrote the file from the wrong list. That corrupted
  # store.yml and left it modified moments after the sync recorded its ledger,
  # which is the drift that appeared right after a sync that had worked.
  def sync_configs
    puts "\n⚙️  Syncing configuration"
    puts "=" * 60

    SiteConfig.db_backed_types.each do |type|
      puts(SiteConfig.sync_from_file(type) ? "  ✓ #{type}" : "  ✗ #{type} failed")
    end

    puts "=" * 60
  end
end
