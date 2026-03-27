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

      puts "\nFetching live data for #{published.count} published posts..." if @verbose

      published.each_with_index do |post, i|
        fetch_post(post)

        # Rate limiting
        sleep(1) if i < published.count - 1
      end

      @manifest_entries
    end

    def fetch_post(post)
      url = build_url(post.slug)
      return unless url

      puts "  Fetching: #{url}" if @verbose

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
      puts "  Error fetching #{post.slug}: #{e.message}" if @verbose
      log_manifest_entry(post, e.message)
    end

    private

    def build_url(slug)
      base = @base_url || @auto_detected_url
      return nil unless base

      "#{base}/p/#{slug}"
    end

    def http_get(url, retries: 1)
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
        http_get(response["location"], retries: retries - 1)
      else
        if retries > 0
          sleep(3)
          http_get(url, retries: retries - 1)
        else
          nil
        end
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED
      if retries > 0
        sleep(3)
        http_get(url, retries: retries - 1)
      else
        nil
      end
    end

    def extract_preloads(html)
      # Search all script tags for _preloads
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
      # Find the JSON.parse call
      start_match = content.match(/window\._preloads\s+=\s+JSON\.parse\("/)
      return nil unless start_match

      start_idx = start_match.end(0)

      # Find the closing ")
      # The script content doesn't include </script>, so look for ")
      end_idx = content.index('")', start_idx)
      return nil unless end_idx

      # The content is an escaped JSON string
      escaped_json = content[start_idx...end_idx]

      # Wrap in quotes and parse as JSON to unescape properly
      # First parse unescapes the string, second parse converts to Hash
      wrapped = '"' + escaped_json + '"'
      json_string = JSON.parse(wrapped)
      JSON.parse(json_string)
    end

    def auto_detect_base_url(preloads)
      return if @base_url || @auto_detected_url

      @auto_detected_url = preloads["base_url"]
      puts "  Auto-detected publication URL: #{@auto_detected_url}" if @verbose && @auto_detected_url
    end

    def extract_post_data(post, preloads)
      post_data = preloads["post"]

      # No post data means paywalled or inaccessible
      unless post_data
        if post.type == "podcast"
          log_manifest_entry(post, "post data not available (paywalled or requires auth)")
          puts "  ⚠ Post data not available (paywalled)" if @verbose
        end
        return
      end

      # Cover image
      post.cover_image = post_data["cover_image"].to_s if post_data["cover_image"]

      # Podcast fields
      if post.type == "podcast"
        post.podcast_url = post_data["podcast_url"].to_s if post_data["podcast_url"]
        post.podcast_duration = post_data["podcast_duration"] if post_data["podcast_duration"]

        podcast_fields = post_data["podcastFields"] || {}
        post.podcast_episode_number = podcast_fields["podcast_episode_number"]
        post.podcast_season_number = podcast_fields["podcast_season_number"]
        post.podcast_episode_type = podcast_fields["podcast_episode_type"]
        post.podcast_episode_image_url = post_data["podcast_episode_image_url"].to_s if post_data["podcast_episode_image_url"]

        # Transcription
        upload = post_data["podcastUpload"] || {}
        transcription = upload["transcription"] || {}
        post.transcription_url = transcription["cdn_url"].to_s if transcription["cdn_url"]

        captions = transcription["signed_captions"] || []
        post.caption_urls = captions.map { |c| c["url"].to_s } if captions.any?
      end

      # Video fields
      video_upload = post_data["videoUpload"]
      if video_upload
        post.video_mux_playback_id = video_upload["mux_playback_id"].to_s if video_upload["mux_playback_id"]

        extracted = video_upload["extractedAudio"]
        if extracted
          post.extracted_audio = {
            transcription_url: extracted.dig("transcription", "cdn_url"),
            caption_urls: (extracted.dig("transcription", "signed_captions") || []).map { |c| c["url"] }
          }
        end
      end

      puts "  ✓ Fetched: #{post.title}" if @verbose

      # Check for missing media and log to manifest
      check_missing_media(post, post_data)
    end

    def check_missing_media(post, post_data)
      return unless post.is_published

      missing_reasons = []

      # Podcast posts need podcast_url
      if post.type == "podcast" && (post.podcast_url.nil? || post.podcast_url.empty?)
        missing_reasons << "podcast_url missing (may be paywalled)"
      end

      # Video posts need video mux_playback_id
      if post.type == "podcast" && post_data["videoUpload"].nil?
        # Only flag if the post looks like a video post (has extracted audio or other video indicators)
        # This is a soft check - not all podcasts are video
      end

      if missing_reasons.any?
        log_manifest_entry(post, missing_reasons.join(", "))
        puts "  ⚠ Missing media: #{missing_reasons.join(", ")}" if @verbose
      end
    end

    def log_manifest_entry(post, reason)
      @manifest_entries << {
        slug: post.slug,
        post_type: post.type,
        post_url: build_url(post.slug),
        audience: post.audience,
        reason: reason,
        podcast_url: post.podcast_url.to_s,
        video_url: post.video_mux_playback_id ? "https://stream.mux.com/#{post.video_mux_playback_id}.m3u8" : "",
        captions_url: (post.caption_urls || []).first.to_s
      }
    end
  end
end
