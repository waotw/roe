# frozen_string_literal: true

module SubstackImporter
  class LiveFetcher
    attr_reader :base_url, :manifest_entries

    def initialize(base_url: nil, verbose: false)
      @base_url = base_url
      @verbose = verbose
      @manifest_entries = []
      @auto_detected_url = nil
    end

    def fetch_posts(posts)
      published = posts.select(&:is_published)

      Rails.logger.info "[SubstackImporter] Fetching live data for #{published.count} published posts..."

      published.each_with_index do |post, i|
        fetch_post(post)
        sleep(0.5) if i < published.count - 1 # Rate limiting
      end

      @manifest_entries
    end

    def fetch_post(post)
      url = build_url(post.slug)
      return unless url

      Rails.logger.debug "[SubstackImporter] Fetching: #{url}"

      html = http_get(url)
      unless html
        log_manifest_entry(post, "Failed to fetch page")
        return
      end

      preloads = extract_preloads(html)
      unless preloads
        log_manifest_entry(post, "No _preloads JSON found")
        return
      end

      auto_detect_base_url(preloads)
      extract_post_data(post, preloads)
    rescue => e
      Rails.logger.error "[SubstackImporter] Error fetching #{post.slug}: #{e.message}"
      log_manifest_entry(post, e.message)
    end

    private

    def build_url(slug)
      base = @base_url || @auto_detected_url
      return nil unless base

      "#{base}/p/#{slug}"
    end

    def http_get(url, retries: 2)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (compatible; SubstackImporter/#{VERSION})"

      response = http.request(request)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPRedirection
        http_get(response["location"], retries: retries - 1) if retries > 0
      else
        if retries > 0
          sleep(2)
          http_get(url, retries: retries - 1)
        else
          nil
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED
      if retries > 0
        sleep(2)
        http_get(url, retries: retries - 1)
      else
        nil
      end
    end

    def extract_preloads(html)
      html.scan(/<script[^>]*>(.*?)<\/script>/m) do |content|
        content = $1
        next unless content.include?("window._preloads")
        data = extract_json_from_script(content)
        return data if data
      end
      nil
    rescue JSON::ParserError
      nil
    end

    def extract_json_from_script(content)
      start_match = content.match(/window\._preloads\s+=\s+JSON\.parse\("/)
      return nil unless start_match

      start_idx = start_match.end(0)
      end_idx = content.index('")', start_idx)
      return nil unless end_idx

      escaped_json = content[start_idx...end_idx]
      wrapped = '"' + escaped_json + '"'
      json_string = JSON.parse(wrapped)
      JSON.parse(json_string)
    end

    def auto_detect_base_url(preloads)
      return if @base_url || @auto_detected_url
      @auto_detected_url = preloads["base_url"]
      Rails.logger.info "[SubstackImporter] Auto-detected publication URL: #{@auto_detected_url}" if @auto_detected_url
    end

    def extract_post_data(post, preloads)
      post_data = preloads["post"]

      unless post_data
        log_manifest_entry(post, "Post data not available (paywalled or requires auth)")
        return
      end

      # Cover image
      if post_data["cover_image"].present?
        post.cover_image = post_data["cover_image"].to_s
        Rails.logger.debug "[SubstackImporter] Found cover image for #{post.slug}"
      elsif post.audience.to_s == "paid" || post.audience.to_s == "premium"
        # Track missing cover image for paid posts
        log_manifest_entry(post, "cover_image missing (paywalled post)")
      end

      # Podcast fields
      if post.type == "podcast"
        if post_data["podcast_url"].present?
          post.podcast_url = post_data["podcast_url"].to_s
        else
          log_manifest_entry(post, "podcast_url missing (may be paywalled)")
        end

        if post_data["podcast_duration"].present?
          post.podcast_duration = post_data["podcast_duration"]
        end

        podcast_fields = post_data["podcastFields"] || {}
        post.podcast_episode_number = podcast_fields["podcast_episode_number"]
        post.podcast_season_number = podcast_fields["podcast_season_number"]
        post.podcast_episode_type = podcast_fields["podcast_episode_type"]

        if post_data["podcast_episode_image_url"].present?
          post.podcast_episode_image_url = post_data["podcast_episode_image_url"].to_s
        end
      end

      # Video fields
      video_upload = post_data["videoUpload"]
      if video_upload && video_upload["mux_playback_id"].present?
        post.video_mux_playback_id = video_upload["mux_playback_id"].to_s
      end

      Rails.logger.debug "[SubstackImporter] Fetched live data for: #{post.title}"
    end

    def log_manifest_entry(post, reason)
      @manifest_entries << {
        slug: post.slug,
        post_type: post.type,
        post_url: build_url(post.slug),
        audience: post.audience,
        reason: reason
      }
    end
  end
end
