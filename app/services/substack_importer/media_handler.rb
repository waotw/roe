# frozen_string_literal: true

module SubstackImporter
  class MediaHandler
    attr_reader :site_root, :downloaded, :url_mappings, :existing_media

    def initialize(site_root:, import: nil, verbose: false, rss_items: nil, ignore_media: false)
      @site_root = site_root
      @import = import
      @verbose = verbose
      @rss_items = rss_items
      # Dry run: rewrite URLs to the expected local paths (body + frontmatter)
      # but download nothing and create no Medium rows, so a later re-run with
      # this off backfills the real files into those exact paths.
      @ignore_media = ignore_media
      @downloaded = []
      @url_mappings = {} # remote_url => local_path
      @existing_media = {} # remote_url => medium record
    end

    def download_all(posts)
      # Pre-load existing media by source_url
      load_existing_media

      posts.each { |post| download_post_media(post) }
      @downloaded
    end

    def download_post_media(post)
      local_media = {}
      local_media[:missing] = []

      local_media[:images] = download_post_images(post)
      local_media[:cover_image] = download_cover_image(post, local_media[:missing])
      local_media[:audio] = download_audio(post, local_media[:missing])
      local_media[:video] = download_video(post, local_media[:missing])
      local_media[:audio_embeds] = download_audio_embeds(post, local_media[:missing])

      local_media
    end

    def replace_urls(markdown)
      result = markdown.dup
      root = File.expand_path(@site_root)

      @url_mappings.each do |remote, local|
        next if local.nil?

        relative = File.expand_path(local).sub(root + "/", "")
        local_path = "/#{relative}"

        # Try exact match first
        if result.include?(remote)
          result = result.gsub(remote, local_path)
          Rails.logger.debug "  Replaced URL: #{remote[0..60]}... -> #{local_path}" if @verbose
        else
          # Try without HTML entities
          decoded = remote.gsub("&amp;", "&")
          if result.include?(decoded)
            result = result.gsub(decoded, local_path)
            Rails.logger.debug "  Replaced decoded URL: #{decoded[0..60]}... -> #{local_path}" if @verbose
          else
            Rails.logger.debug "  URL not found in markdown: #{remote[0..60]}..." if @verbose
          end
        end
      end

      result
    end

    private

    def load_existing_media
      return unless @import.present?

      Medium.where.not(source_url: nil).find_each do |medium|
        @existing_media[medium.source_url] = medium
      end
    end

    def download_post_images(post)
      converter = Converter.new
      return [] unless post.html_content

      converter.convert(post.html_content)
      images = converter.collected_images
      downloaded_paths = []

      images.each_with_index do |img, i|
        src = img[:src]
        next if src.nil? || src.empty? || src.start_with?("/")

        # Skip cover image - it's handled separately by download_cover_image
        next if post.cover_image.present? && src == post.cover_image

        ext = File.extname(URI.parse(src).path).split("?").first
        ext = ".jpg" if ext.nil? || ext.empty?
        filename = "#{post.slug}-#{i + 1}#{ext}"

        path = download_image(src, filename)
        downloaded_paths << path if path
      end

      downloaded_paths
    rescue URI::InvalidURIError => e
      Rails.logger.error "  Invalid image URL: #{e.message}" if @verbose
      []
    end

    def download_cover_image(post, missing)
      # For podcast episodes, prefer the per-episode artwork from the RSS
      # itunes:image (when an RSS feed was provided). Substack hosts a
      # different image per episode in the feed, separate from the
      # post's cover image — this gives every episode its own artwork.
      src = rss_episode_image_for(post) || post.cover_image
      return nil if src.nil? || src.empty?
      return nil if src.start_with?("/")

      begin
        ext = File.extname(URI.parse(src).path).split("?").first
        ext = ".jpg" if ext.nil? || ext.empty?
        filename = "#{post.slug}-cover#{ext}"
        expected_path = "/media/images/#{filename}"

        result = download_image(src, filename)

        # Track missing cover image
        if result.nil? && missing
          missing << { type: "cover_image", url: src, slug: post.slug, expected_path: expected_path }
        end

        result
      rescue URI::InvalidURIError => e
        Rails.logger.error "  Invalid cover image URL: #{e.message}" if @verbose
        nil
      end
    end

    def rss_episode_image_for(post)
      return nil unless @rss_items
      item = @rss_items[post.id.to_s]
      item && item["image_url"].presence
    end

    def rss_audio_url_for(post)
      return nil unless @rss_items
      item = @rss_items[post.id.to_s]
      item && item["enclosure_url"].presence
    end

    def download_image(url, filename)
      dest = File.join(@site_root, "media", "images", filename)
      file_path = "/media/images/#{filename}"

      # Ignore-media dry run: map the URL to its expected local path (so the
      # body is rewritten and the frontmatter points local) but download
      # nothing and write no Medium row.
      if @ignore_media
        @url_mappings[url] = dest
        return file_path
      end

      # Check if we already have this image from a previous import (database record)
      if @existing_media.key?(url)
        medium = @existing_media[url]
        @url_mappings[url] = File.join(@site_root, medium.file_path.sub(%r{^/}, ""))
        Rails.logger.debug "  Reusing tracked image: #{filename}" if @verbose
        return medium.file_path
      end

      # Skip if already exists on disk (from old CLI import or manual upload)
      if File.exist?(dest)
        @url_mappings[url] = dest
        # Create medium record WITHOUT associating to this import
        # This prevents rollback from deleting pre-existing files
        medium = Medium.find_or_initialize_by(file_path: file_path)
        if medium.new_record?
          medium.source_url = url
          medium.import = nil  # Don't associate with this import!
          medium.uploaded_at = File.mtime(dest)  # Use file modification time
          medium.save!
          Rails.logger.info "  Tracked pre-existing image: #{filename}"
        end
        return file_path
      end

      result = download_file(url, dest)
      if result
        # Convert HEIC to JPEG if needed (only if vips is available)
        result = convert_heic_if_needed(result, dest)

        # Update file_path if conversion changed the extension
        if result != dest
          file_path = "/media/images/#{File.basename(result)}"
        end

        @url_mappings[url] = result
        # Upsert by file_path. Plain create! collides when a Medium row
        # already exists at this path — happens when the user deleted the
        # file from disk but the DB row survived, or when the URL rotated
        # (RSS tokens change per session) so the source_url lookup missed.
        upsert_medium!(file_path: file_path, source_url: url, uploaded_at: Time.current)
        file_path
      end
    end

    def convert_heic_if_needed(downloaded_path, original_dest)
      ext = File.extname(downloaded_path).downcase

      # Check if it's a HEIC file
      return downloaded_path unless [ ".heic", ".heif" ].include?(ext)

      # Check if vips is available before attempting conversion
      unless vips_available?
        Rails.logger.warn "  HEIC file detected but vips not available, skipping conversion: #{File.basename(downloaded_path)}" if @verbose
        return downloaded_path
      end

      Rails.logger.info "  Converting HEIC to JPEG: #{File.basename(downloaded_path)}" if @verbose

      begin
        require "image_processing/vips"

        # Create JPEG version with same base name
        jpeg_path = downloaded_path.sub(/\.heic$/i, ".jpg").sub(/\.heif$/i, ".jpg")

        # Convert using vips
        ImageProcessing::Vips
          .source(downloaded_path)
          .convert("jpg")
          .saver(quality: 90)
          .call(destination: jpeg_path)

        # Delete the original HEIC file
        File.delete(downloaded_path)

        Rails.logger.info "  Converted to: #{File.basename(jpeg_path)}" if @verbose
        jpeg_path
      rescue => e
        Rails.logger.error "  HEIC conversion failed: #{e.message}" if @verbose
        # Return original path if conversion fails
        downloaded_path
      end
    end

    def vips_available?
      @vips_available ||= begin
        require "ruby-vips"
        Vips.version_string
        true
      rescue LoadError, NameError
        false
      end
    end

    def download_audio(post, missing)
      # Prefer the RSS enclosure URL (authoritative, includes paid-feed
      # token) over the live-fetched podcast_url. Falls back when no
      # RSS data was provided.
      url = rss_audio_url_for(post) || post.podcast_url
      expected_path = "/media/audio/#{post.slug}.mp3"

      return nil if url.nil? || url.empty?

      filename = "#{post.slug}.mp3"
      dest = File.join(@site_root, "media", "audio", filename)
      file_path = "/media/audio/#{filename}"

      if @ignore_media
        @url_mappings[url] = dest
        return file_path
      end

      # Check if we already have this audio in database
      existing = Medium.find_by(source_url: url)
      if existing
        Rails.logger.debug "  Reusing tracked audio: #{filename}" if @verbose
        return existing.file_path
      end

      # Skip if already exists on disk (from old CLI import)
      if File.exist?(dest)
        medium = Medium.find_or_initialize_by(file_path: file_path)
        if medium.new_record?
          medium.source_url = url
          medium.import = nil  # Don't associate with this import!
          medium.uploaded_at = File.mtime(dest)
          medium.save!
          Rails.logger.info "  Tracked pre-existing audio: #{filename}"
        end
        return file_path
      end

      result = download_file(url, dest)
      if result
        upsert_medium!(file_path: file_path, source_url: url, uploaded_at: Time.current)
        file_path
      else
        # Track missing audio with expected path
        missing << { type: "audio", url: url, slug: post.slug, expected_path: expected_path }
        nil
      end
    end

    def download_video(post, missing)
      # Substack videos use Mux for hosting
      # The video_mux_playback_id is used to construct the video URL
      mux_id = post.video_mux_playback_id
      expected_path = "/media/video/#{post.slug}.mp4"

      return nil if mux_id.nil? || mux_id.empty?

      # Construct Mux video URL
      url = "https://stream.mux.com/#{mux_id}/high.mp4"

      filename = "#{post.slug}.mp4"
      dest = File.join(@site_root, "media", "video", filename)
      file_path = "/media/video/#{filename}"

      if @ignore_media
        @url_mappings[url] = dest
        return file_path
      end

      # Check if we already have this video in database
      existing = Medium.find_by(source_url: url)
      if existing
        Rails.logger.debug "  Reusing tracked video: #{filename}" if @verbose
        return existing.file_path
      end

      # Skip if already exists on disk (from old CLI import)
      if File.exist?(dest)
        medium = Medium.find_or_initialize_by(file_path: file_path)
        if medium.new_record?
          medium.source_url = url
          medium.import = nil  # Don't associate with this import!
          medium.uploaded_at = File.mtime(dest)
          medium.save!
          Rails.logger.info "  Tracked pre-existing video: #{filename}"
        end
        return file_path
      end

      result = download_file(url, dest)
      if result
        upsert_medium!(file_path: file_path, source_url: url, uploaded_at: Time.current)
        file_path
      else
        # Track missing video with expected path
        missing << { type: "video", url: url, mux_id: mux_id, slug: post.slug, expected_path: expected_path }
        nil
      end
    end

    # Inline native-audio embeds (AudioPlaceholder) carry only a
    # mediaUploadId, so the download URL is reconstructed from the
    # publication host. Substack serves the file at /api/v1/audio/upload/
    # <id>/src, which 302-redirects to the real asset (download_file follows
    # redirects). The Converter already emitted the local /media/audio path
    # into the markdown, so there's nothing to rewrite here — we just need
    # the file to land at that path. Returns the local paths downloaded.
    def download_audio_embeds(post, missing)
      return [] unless post.html_content

      host = substack_media_host
      # Without a publication host we can't build the fetch URL. Flag each
      # embed as missing so it surfaces in the resolution UI rather than
      # silently leaving a dead player.
      converter = Converter.new
      converter.convert(post.html_content)
      embeds = converter.collected_audio
      return [] if embeds.empty?

      downloaded = []

      embeds.each do |embed|
        filename = embed[:filename]
        dest = File.join(@site_root, "media", "audio", filename)
        file_path = "/media/audio/#{filename}"
        url = host ? "https://#{host}/api/v1/audio/upload/#{embed[:media_id]}/src" : nil

        if @ignore_media
          # Dry run: the markdown already points at file_path; a later
          # backfill re-run downloads it. Create no Medium row.
          downloaded << file_path
          next
        end

        if url.nil?
          missing << { type: "audio_embed", url: nil, media_id: embed[:media_id], slug: post.slug, expected_path: file_path }
          next
        end

        # Reuse a previously-downloaded file (tracked by source_url).
        if (existing = Medium.find_by(source_url: url))
          Rails.logger.debug "  Reusing tracked audio embed: #{filename}" if @verbose
          downloaded << existing.file_path
          next
        end

        # Already on disk (prior import / manual upload) — track without
        # associating to this import so rollback can't delete it.
        if File.exist?(dest)
          medium = Medium.find_or_initialize_by(file_path: file_path)
          if medium.new_record?
            medium.source_url = url
            medium.import = nil
            medium.uploaded_at = File.mtime(dest)
            medium.save!
            Rails.logger.info "  Tracked pre-existing audio embed: #{filename}"
          end
          downloaded << file_path
          next
        end

        result = download_file(url, dest)
        if result
          upsert_medium!(file_path: file_path, source_url: url, uploaded_at: Time.current)
          downloaded << file_path
        else
          missing << { type: "audio_embed", url: url, media_id: embed[:media_id], slug: post.slug, expected_path: file_path }
        end
      end

      downloaded
    end

    # Bare hostname of the publication being imported (e.g. "foo.substack.com"),
    # derived from the configured base URL. Tolerates a missing scheme the same
    # way the Converter does. Returns nil when no usable base URL is set.
    def substack_media_host
      raw = @import&.base_url.to_s.strip
      return nil if raw.empty?

      raw = "https://#{raw}" unless raw.match?(%r{\A[a-z][a-z0-9+.\-]*://}i)
      URI.parse(raw).host
    rescue URI::InvalidURIError
      nil
    end

    # Upsert a Medium row for a freshly-downloaded file. Replaces plain
    # Medium.create! at the end of each download_* method so we don't trip
    # the file_path UNIQUE constraint when:
    #   - The file was deleted from disk but the DB row was left behind
    #     (orphaned record from a prior import that wasn't rolled back).
    #   - The source_url changed between imports (e.g. RSS enclosure URLs
    #     with rotating session tokens) so the find_by(source_url:) lookup
    #     missed an existing row that points at the same destination path.
    #   - The ContentWatcher (Listen-based file watcher) sees the freshly
    #     downloaded file land in site/media/ and races us to insert the
    #     Medium row before our save! runs. find_or_initialize_by checked
    #     before the watcher's insert, save! runs after — UNIQUE blows up.
    # Always re-associates with the current import so rollback can clean
    # up the freshly-downloaded file.
    def upsert_medium!(file_path:, source_url:, uploaded_at:)
      medium = Medium.find_or_initialize_by(file_path: file_path)
      medium.source_url = source_url
      medium.import = @import
      medium.uploaded_at = uploaded_at
      medium.save!
      medium
    rescue ActiveRecord::RecordNotUnique
      # Lost the race with ContentWatcher. Re-fetch the row it inserted
      # and stamp our import association onto it so rollback still works.
      medium = Medium.find_by!(file_path: file_path)
      medium.update!(source_url: source_url, import: @import, uploaded_at: uploaded_at)
      medium
    end

    def download_file(url, dest, redirect_limit: 5)
      return dest if File.exist?(dest)
      if redirect_limit <= 0
        Rails.logger.error "[SubstackImporter] Too many redirects when downloading: #{url}"
        return nil
      end

      FileUtils.mkdir_p(File.dirname(dest))

      Rails.logger.debug "  Downloading: #{url} -> #{dest}" if @verbose

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 15
      # Large podcasts can take a few minutes on slower connections.
      # The previous 120s default was tripping for ~60MB+ episodes.
      http.read_timeout = 600

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; SubstackImporter/#{VERSION})"

      # Stream the body straight to disk so we never hold the whole file
      # in memory — important for hour-long podcast MP3s.
      result = nil
      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          File.open(dest, "wb") do |f|
            response.read_body { |chunk| f.write(chunk) }
          end
          @downloaded << dest
          result = dest
        when Net::HTTPRedirection
          new_url = response["location"]
          if new_url.present?
            new_url = URI.join(url, new_url).to_s unless new_url.start_with?("http")
            result = download_file(new_url, dest, redirect_limit: redirect_limit - 1)
          else
            Rails.logger.error "[SubstackImporter] Redirect without location header for #{url}"
          end
        else
          Rails.logger.error "[SubstackImporter] Download failed: HTTP #{response.code} #{response.message} for #{url}"
        end
      end

      result
    rescue Net::ReadTimeout, Net::OpenTimeout => e
      Rails.logger.error "[SubstackImporter] Timeout downloading #{url}: #{e.message}"
      File.delete(dest) if File.exist?(dest)  # clean up any partial file
      nil
    rescue => e
      Rails.logger.error "[SubstackImporter] Download error (#{e.class}) for #{url}: #{e.message}"
      File.delete(dest) if File.exist?(dest)
      nil
    end
  end
end
