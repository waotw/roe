# frozen_string_literal: true

module SubstackImporter
  class MediaHandler
    attr_reader :site_root, :downloaded, :url_mappings, :existing_media

    def initialize(site_root:, import: nil, verbose: false)
      @site_root = site_root
      @import = import
      @verbose = verbose
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
      return nil if post.cover_image.nil? || post.cover_image.empty?

      src = post.cover_image
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

    def download_image(url, filename)
      # Check if we already have this image from a previous import (database record)
      if @existing_media.key?(url)
        medium = @existing_media[url]
        @url_mappings[url] = File.join(@site_root, medium.file_path.sub(%r{^/}, ""))
        Rails.logger.debug "  Reusing tracked image: #{filename}" if @verbose
        return medium.file_path
      end

      dest = File.join(@site_root, "media", "images", filename)
      file_path = "/media/images/#{filename}"

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
        @url_mappings[url] = result
        # Create medium record and associate with this import (for rollback tracking)
        Medium.create!(
          file_path: file_path,
          source_url: url,
          import: @import,
          uploaded_at: Time.current
        )
        file_path
      end
    end

    def download_audio(post, missing)
      url = post.podcast_url
      expected_path = "/media/audio/#{post.slug}.mp3"

      return nil if url.nil? || url.empty?

      filename = "#{post.slug}.mp3"
      dest = File.join(@site_root, "media", "audio", filename)
      file_path = "/media/audio/#{filename}"

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
        # Create medium record and associate with this import
        Medium.create!(
          file_path: file_path,
          source_url: url,
          import: @import,
          uploaded_at: Time.current
        )
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
        # Create medium record and associate with this import
        Medium.create!(
          file_path: file_path,
          source_url: url,
          import: @import,
          uploaded_at: Time.current
        )
        file_path
      else
        # Track missing video with expected path
        missing << { type: "video", url: url, mux_id: mux_id, slug: post.slug, expected_path: expected_path }
        nil
      end
    end

    def download_file(url, dest, redirect_limit: 5)
      return dest if File.exist?(dest)
      return nil if redirect_limit <= 0

      FileUtils.mkdir_p(File.dirname(dest))

      Rails.logger.debug "  Downloading: #{url} -> #{dest}" if @verbose

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 15
      http.read_timeout = 120

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; SubstackImporter/#{VERSION})"

      response = http.request(request)

      case response
      when Net::HTTPSuccess
        File.binwrite(dest, response.body)
        @downloaded << dest
        dest
      when Net::HTTPRedirection
        # Follow redirect
        new_url = response["location"]
        if new_url
          # Handle relative redirects
          new_url = URI.join(url, new_url).to_s unless new_url.start_with?("http")
          download_file(new_url, dest, redirect_limit: redirect_limit - 1)
        else
          Rails.logger.error "  Redirect without location: #{url}" if @verbose
          nil
        end
      else
        Rails.logger.error "  Download failed (#{response.code}): #{url}" if @verbose
        nil
      end
    rescue => e
      Rails.logger.error "  Download error: #{e.message}" if @verbose
      nil
    end
  end
end
