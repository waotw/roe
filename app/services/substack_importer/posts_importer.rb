# frozen_string_literal: true

module SubstackImporter
  class PostsImporter
    attr_reader :import, :stats, :errors

    def initialize(import)
      @import = import
      @stats = {
        posts_created: 0,
        posts_skipped: 0,
        media_downloaded: 0,
        media_reused: 0,
        missing_media: [],
        errors: []
      }
      @errors = []
    end

    def run
      @import.update!(status: :importing_posts, started_at: Time.current)

      Rails.logger.info "[SubstackImporter] Starting import #{@import.id}"
      Rails.logger.info "[SubstackImporter] Configuration: #{@import.configuration.inspect}"
      Rails.logger.info "[SubstackImporter] Filters: #{@import.filters.inspect}"
      Rails.logger.info "[SubstackImporter] Options: #{@import.options.inspect}"

      # Extract ZIP
      extract_path = extract_archive
      return false unless extract_path

      Rails.logger.info "[SubstackImporter] Extracted to: #{extract_path}"

      # List extracted files for debugging
      if Dir.exist?(extract_path)
        files = Dir.glob(File.join(extract_path, "**", "*")).select { |f| File.file?(f) }
        Rails.logger.info "[SubstackImporter] Extracted files: #{files.inspect}"
      end

      # Find the CSV file
      csv_path = find_csv_file(extract_path)
      unless csv_path
        Rails.logger.error "[SubstackImporter] No CSV file found in #{extract_path}"
        @import.mark_failed!("No CSV file found in export")
        return false
      end

      Rails.logger.info "[SubstackImporter] Using CSV: #{csv_path}"

      # Parse CSV
      begin
        csv_parser = CsvParser.new(csv_path)
        posts = csv_parser.parse
      rescue => e
        Rails.logger.error "[SubstackImporter] CSV parsing failed: #{e.message}"
        @import.mark_failed!("CSV parsing failed: #{e.message}")
        return false
      end

      Rails.logger.info "[SubstackImporter] Found #{posts.count} posts in CSV"

      if posts.empty?
        Rails.logger.warn "[SubstackImporter] No posts found in CSV!"
        @import.mark_failed!("No posts found in CSV")
        return false
      end

      # Filter posts
      filtered_posts = csv_parser.filter(
        drafts: @import.options["include_drafts"],
        type: @import.filters["type"],
        after: @import.filters["after"],
        before: @import.filters["before"]
      )

      Rails.logger.info "[SubstackImporter] After filtering: #{filtered_posts.count} posts"

      # Load HTML content
      posts_dir = find_posts_dir(extract_path)
      Rails.logger.info "[SubstackImporter] Looking for HTML in: #{posts_dir}"

      html_loader = HtmlLoader.new(posts_dir)
      html_loader.load
      match_result = html_loader.match_to_posts(filtered_posts)

      Rails.logger.info "[SubstackImporter] Matched #{match_result[:matched]} posts with HTML"

      if match_result[:unmatched_posts].any?
        Rails.logger.warn "[SubstackImporter] #{match_result[:unmatched_posts].count} posts without HTML"
        match_result[:unmatched_posts].each do |post|
          Rails.logger.warn "[SubstackImporter]   - #{post.slug} (ID: #{post.id})"
        end
      end

      # Fetch live data for cover images and podcast URLs
      # Only fetch for posts that don't already exist (to speed up re-imports)
      if @import.base_url.present?
        posts_needing_live_data = filtered_posts.reject do |post|
          ::Post.exists?([ "json_extract(metadata, '$.substack_post_id') = ?", post.id ])
        end

        if posts_needing_live_data.any?
          Rails.logger.info "[SubstackImporter] Fetching live data for #{posts_needing_live_data.count} new posts from #{@import.base_url}..."
          live_fetcher = LiveFetcher.new(base_url: @import.base_url, verbose: Rails.env.development?)
          live_fetcher.fetch_posts(posts_needing_live_data)

          if live_fetcher.manifest_entries.any?
            Rails.logger.warn "[SubstackImporter] #{live_fetcher.manifest_entries.count} posts with missing media from live fetch"
            @stats[:missing_media] ||= []
            live_fetcher.manifest_entries.each do |entry|
              @stats[:missing_media] << {
                slug: entry[:slug],
                items: [ { type: entry[:post_type], reason: entry[:reason] } ]
              }
            end
          end
        else
          Rails.logger.info "[SubstackImporter] All posts already exist, skipping live data fetch"
        end
      else
        Rails.logger.warn "[SubstackImporter] No base_url provided, skipping live data fetch"
      end

      # Build the RSS lookup map (substack_post_id → rss_item) once,
      # passed to media_handler and frontmatter so they can prefer RSS
      # data for podcasts when available.
      rss_items = @import.rss_items_by_post_id
      podcast_key = derive_podcast_key_from_rss(rss_items)

      # Setup media handler
      site_root = RoeSitePaths::SITE_PATH.to_s
      media_handler = MediaHandler.new(
        site_root: site_root,
        import: @import,
        verbose: Rails.env.development?,
        rss_items: rss_items,
        ignore_media: @import.options["ignore_media"] == "1"
      )

      # Setup frontmatter builder
      frontmatter = Frontmatter.new(
        site_root: site_root,
        default_published_to: @import.options["default_published_to"],
        rss_items: rss_items,
        podcast_key: podcast_key
      )

      # If we have RSS channel data, seed/update the podcast.yml entry so
      # imported episodes' `podcast: <key>` field references a valid show.
      seed_podcast_config_from_rss(podcast_key) if podcast_key

      # Setup converter. base_url is the user-supplied Substack
      # publication URL captured in the importer's first setup step;
      # the converter uses it to recognise internal links so they get
      # rewritten to root-relative paths on the destination Roe site
      # instead of remaining as live URLs back to Substack.
      converter = Converter.new(
        verbose: Rails.env.development?,
        insert_paywalls: @import.options["insert_paywalls"] == "1",
        paywall_text: @import.options["paywall_text"].presence,
        paywall_button_text: @import.options["paywall_button_text"].presence,
        substack_url: @import.base_url
      )

      # Process each post
      processed_count = 0
      filtered_posts.each do |post|
        process_post(post, converter, frontmatter, media_handler)
        processed_count += 1
      end

      Rails.logger.info "[SubstackImporter] Processed #{processed_count} posts"
      Rails.logger.info "[SubstackImporter] Stats: #{@stats.inspect}"

      # Update stats
      @import.update!(
        status: :completed,
        stats: @import.stats.merge(@stats),
        completed_at: Time.current
      )

      # Drop the RSS data now that we're done with it. The parsed feed
      # contains token-bearing enclosure URLs we don't want lingering
      # in the DB after the import is finished.
      @import.scrub_rss_data!

      # Complete phase 2
      @import.complete_phase!(2)

      # If no email list exists in the export, auto-complete phases 3 and 4
      # so the user doesn't have to step through them manually
      unless email_list_exists?
        Rails.logger.info "[SubstackImporter] No email list found, auto-completing phases 3 and 4"
        skipped_stats = {
          members_skipped_reason: "No email list found in export — member and delivery import skipped",
          deliveries_skipped_reason: "No email list found in export — member and delivery import skipped"
        }
        @import.update!(stats: @import.stats.merge(skipped_stats))
        @import.complete_phase!(3)
        @import.complete_phase!(4)
      end

      true
    rescue => e
      Rails.logger.error "[SubstackImporter] Import failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @import.mark_failed!(e.message)
      false
    end
    # Note: don't clean up the extract directory here. Phases 3 (members) and
    # 4 (deliveries) still need it. Cleanup happens via Import#cleanup_temp_files!
    # when the import record is destroyed (see Admin::ImportsController#destroy).

    def rollback
      return false unless @import.can_rollback?

      Rails.logger.info "[SubstackImporter] Rolling back import #{@import.id}"

      # Delete posts created by this import. Remove the markdown file from
      # disk alongside destroying the DB row: destroy_all on its own leaves
      # the .md on disk, and the content watcher would then re-import it
      # straight back into the database. Delete the file first so the
      # watcher can't recreate the record mid-rollback.
      posts_deleted = @import.posts.count
      site_root = File.expand_path(RoeSitePaths::SITE_PATH)
      @import.posts.find_each do |post|
        path = post.file_path
        if path.present? && File.expand_path(path).start_with?(site_root + "/") && File.exist?(path)
          FileUtils.rm_f(path)
        end
        post.destroy
      end

      # Delete media created by this import
      media_deleted = @import.media.count
      @import.media.find_each do |medium|
        # Delete file from disk
        full_path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, ""))
        FileUtils.rm_f(full_path) if File.exist?(full_path)
        medium.destroy
      end

      @import.update!(status: :rolled_back)

      Rails.logger.info "[SubstackImporter] Rollback complete: #{posts_deleted} posts, #{media_deleted} media files"

      { posts_deleted: posts_deleted, media_deleted: media_deleted }
    end

    private

    def extract_archive
      Rails.logger.info "[SubstackImporter] Archive path: #{@import.archive_path}"
      Rails.logger.info "[SubstackImporter] Extract path: #{@import.extract_path}"

      @extractor = Extractor.new(@import.archive_path, extract_path: @import.extract_path)
      result = @extractor.extract

      Rails.logger.info "[SubstackImporter] Extracted to: #{result}"
      result
    rescue => e
      Rails.logger.error "[SubstackImporter] Extraction failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      @errors << "Extraction failed: #{e.message}"
      @import.mark_failed!("Extraction failed: #{e.message}")
      nil
    end

    def process_post(post, converter, frontmatter, media_handler)
      # Check if post already exists (by substack_post_id)
      # Use ::Post to reference the Rails model, not SubstackImporter::Post struct
      existing = ::Post.find_by("json_extract(metadata, '$.substack_post_id') = ?", post.id)

      if existing
        Rails.logger.debug "[SubstackImporter] Post already exists: #{post.slug}"

        # Still ensure media exists (in case previous import was incomplete)
        # But don't track as "downloaded" for this import
        local_media = media_handler.download_post_media(post)

        # Track missing media for existing posts too
        if local_media[:missing].any?
          @stats[:missing_media] ||= []
          @stats[:missing_media] << { slug: post.slug, items: local_media[:missing] }
        end

        @stats[:posts_skipped] += 1
        return
      end

      # Convert HTML to Markdown
      markdown_body = converter.convert(post.html_content.to_s)

      # Download media for this post. When "Ignore all media" is set the
      # handler writes expected local URLs without downloading anything, so
      # the downloaded stat should stay at zero (a later re-run backfills).
      local_media = media_handler.download_post_media(post)
      unless @import.options["ignore_media"] == "1"
        @stats[:media_downloaded] += local_media[:images].count
        @stats[:media_downloaded] += 1 if local_media[:cover_image]
        @stats[:media_downloaded] += 1 if local_media[:audio]
        @stats[:media_downloaded] += 1 if local_media[:video]
      end

      # Duration is left blank at import time. The metadata-editor
      # controller auto-extracts it from the audio file via the browser's
      # HTML5 element on first page load (see autoExtractDurationIfMissing).
      # Server-side extraction would require ffmpeg/streamio-ffmpeg which
      # the project intentionally avoids depending on.

      # Track missing media
      if local_media[:missing].any?
        @stats[:missing_media] ||= []
        @stats[:missing_media] << { slug: post.slug, items: local_media[:missing] }
      end

      # Replace remote URLs with local paths
      markdown_body = media_handler.replace_urls(markdown_body)

      # Build frontmatter
      frontmatter_yaml = frontmatter.to_yaml(post, local_media: local_media)

      # Build file path
      file_path = build_file_path(post)

      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(file_path))

      # Write file
      content = "#{frontmatter_yaml}\n#{markdown_body}\n"
      File.write(file_path, content)

      # Create Post record via ContentSync
      # Use ::Post to reference the Rails model
      post_record = ::Post.create_or_update_from_file(file_path)

      if post_record.is_a?(::Post)
        post_record.update!(import: @import)
        @stats[:posts_created] += 1
        Rails.logger.info "[SubstackImporter] Created post: #{post.slug}"
      else
        @stats[:posts_skipped] += 1
        Rails.logger.warn "[SubstackImporter] Post creation returned warning for: #{post.slug}"
      end
    rescue => e
      Rails.logger.error "[SubstackImporter] Failed to process post #{post.slug}: #{e.message}"
      @stats[:errors] << "#{post.slug}: #{e.message}"
    end

    def build_file_path(post)
      base_path = if post.type == "page"
        File.join(RoeSitePaths::SITE_PATH, "pages")
      else
        File.join(RoeSitePaths::SITE_PATH, "posts")
      end

      # Posts go directly in /site/posts/ (no date subdirectories)
      File.join(base_path, "#{post.slug}.md")
    end

    def email_list_exists?
      extract_path = @import.extract_path
      return false unless extract_path.present? && Dir.exist?(extract_path)

      Dir.glob(File.join(extract_path, "email_list*.csv")).any?
    end

    def find_csv_file(extract_path)
      # First try the standard name
      standard_path = File.join(extract_path, "posts.csv")
      return standard_path if File.exist?(standard_path)

      # Otherwise find any CSV that looks like posts data
      csv_files = Dir.glob(File.join(extract_path, "*.csv"))
      Rails.logger.info "[SubstackImporter] Found CSV files: #{csv_files.inspect}"

      # Return the first CSV that contains posts or post data
      csv_files.find { |f| File.basename(f).match?(/post/i) } || csv_files.first
    end

    def find_posts_dir(extract_path)
      # First try the standard posts/ directory
      standard_dir = File.join(extract_path, "posts")
      return standard_dir if Dir.exist?(standard_dir)

      # Otherwise just use the extract root (files might be flat)
      extract_path
    end

    # Derive a slug-style podcast key from the RSS channel title
    # (e.g. "Expressive Egg Podcast" → "expressive-egg-podcast"). Used
    # both as the key in podcast.yml and as the value of each imported
    # episode's `podcast:` field. Returns nil if no RSS data.
    def derive_podcast_key_from_rss(rss_items)
      return nil unless rss_items
      channel = @import.rss_data["channel"] || @import.rss_data[:channel] || {}
      title = channel["title"] || channel[:title]
      return nil if title.blank?
      PodcastConfigSeeder.derive_key(title)
    end

    # Create or update a podcast.yml entry from the RSS channel data so
    # imported episodes' `podcast:` references resolve. Downloads the
    # podcast artwork to /site/system/assets/images/<key>-artwork.<ext>.
    def seed_podcast_config_from_rss(podcast_key)
      channel = @import.rss_data["channel"] || @import.rss_data[:channel]
      return unless channel

      seeder = PodcastConfigSeeder.new(podcast_key, channel.transform_keys(&:to_s))
      seeder.seed!
      Rails.logger.info "[SubstackImporter] Seeded podcast.yml entry: #{podcast_key}"
    rescue => e
      Rails.logger.error "[SubstackImporter] Failed to seed podcast config for #{podcast_key}: #{e.message}"
    end
  end
end
