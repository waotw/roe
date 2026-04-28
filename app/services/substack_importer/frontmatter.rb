# frozen_string_literal: true

module SubstackImporter
  class Frontmatter
    def initialize(site_root:, default_published_to: nil, rss_items: nil, podcast_key: nil)
      @site_root = site_root
      # Default to "site" when not set so imported posts always have a
      # valid published_to and don't trigger missing-required warnings.
      @default_published_to = default_published_to.presence || "site"
      # Optional RSS lookup map (substack_post_id → rss item hash). When
      # present, the importer uses RSS data as the source of truth for
      # podcast episodes (guid, duration, image, explicit, author).
      @rss_items = rss_items
      @podcast_key = podcast_key
    end

    def build(post, local_media: {})
      fm = {}

      fm["substack_post_id"] = post.id.to_s
      fm["url_name"] = post.slug.to_s
      fm["title"] = post.title.to_s
      fm["subtitle"] = post.subtitle.to_s
      fm["date"] = format_date(post.date)
      fm["post_type"] = map_post_type(post.type)
      fm["status"] = post.is_published ? "published" : "draft"
      fm["audience"] = map_audience(post.audience)

      # published_to (posts only — pages are site-only by Roe convention).
      if post.type != "page"
        fm["published_to"] = @default_published_to
      end

      # Image: prefer per-episode RSS artwork for podcasts (downloaded by
      # media_handler); fall back to cover image / expected path / remote URL.
      rss_item = rss_item_for(post)
      image_path = local_media[:cover_image] || expected_image_path(post) || resolve_image_path(post)
      fm["image"] = image_path if image_path.present?

      # Podcast-specific fields. When RSS data is available it's the source
      # of truth (it comes straight from Substack's authoritative feed);
      # otherwise we fall back to live_fetcher / CSV data.
      if post.type == "podcast"
        # Only assign to a podcast feed if this episode was actually IN the
        # RSS feed (i.e., Substack listed it as part of that show — paid
        # "podcast" posts that weren't subscribable on Substack don't
        # belong in Roe's RSS feed for this show either). The user can
        # opt in manually by adding `podcast: <key>` to the post's
        # frontmatter later.
        fm["podcast"] = @podcast_key if @podcast_key.present? && rss_item

        fm["episode_number"] = post.podcast_episode_number if post.podcast_episode_number
        fm["season"] = post.podcast_season_number if post.podcast_season_number
        fm["episode_type"] = post.podcast_episode_type.to_s if post.podcast_episode_type

        # Audio: write the expected path for every podcast post unless it's
        # clearly video-only. "Clearly video-only" = a Mux video is set AND
        # no audio source was reported (no podcast_url from Substack, no
        # RSS enclosure). Substack's "local-only" podcasts (audio episodes
        # never published to a public RSS feed) often have neither a
        # podcast_url nor an RSS item, but the user still needs the audio
        # path written so the admin's "missing media" resolver gives them
        # a place to drop the file.
        audio_path = local_media[:audio]
        if audio_path.nil?
          has_audio_source = post.podcast_url.present? || rss_item&.dig("enclosure_url").present?
          is_video_only = post.video_mux_playback_id.present? && !has_audio_source
          audio_path = expected_audio_path(post) unless is_video_only
        end
        fm["audio"] = audio_path if audio_path.present?

        # Duration: prefer RSS itunes:duration (clean integer seconds);
        # fall back to live-fetched podcast_duration.
        duration_seconds = rss_item&.dig("duration").presence&.to_i
        duration_seconds ||= post.podcast_duration.to_f.to_i if post.podcast_duration.present?
        if duration_seconds && duration_seconds > 0
          fm["duration"] = format(
            "%02d:%02d:%02d",
            duration_seconds / 3600,
            (duration_seconds % 3600) / 60,
            duration_seconds % 60
          )
        end

        # GUID: from RSS only. Substack format is `substack:post:NNN` and
        # we store it as-is so podcast subscribers' apps see the same GUID
        # they did from Substack — no migration-day re-download spam.
        fm["guid"] = rss_item["guid"] if rss_item && rss_item["guid"].present?

        # Explicit: RSS itunes:explicit is "Yes"/"No" (sometimes
        # "true"/"false"). Map to Roe's boolean string.
        if rss_item && rss_item["explicit"].present?
          fm["explicit"] = %w[yes true].include?(rss_item["explicit"].to_s.downcase) ? "true" : "false"
        end

        # Author: per-episode override from RSS itunes:author.
        if rss_item && rss_item["author"].present?
          fm["author"] = rss_item["author"]
        end
      end

      # Video-specific fields
      if post.type == "video" || local_media[:video].present? || post.video_mux_playback_id.present?
        # Video: always add expected path
        video_path = local_media[:video] || expected_video_path(post)
        fm["video"] = video_path if video_path.present?
        fm["video_mux_playback_id"] = post.video_mux_playback_id if post.video_mux_playback_id.present?
      end

      fm
    end

    def to_yaml(post, local_media: {})
      fm = build(post, local_media: local_media)
      "---\n#{fm.map { |k, v| "#{k}: #{v.inspect}" }.join("\n")}\n---"
    end

    private

    def map_post_type(type)
      case type.to_s
      when "newsletter" then "article"
      when "podcast" then "podcast"
      when "video" then "video"
      when "page" then "page"
      else "article"
      end
    end

    def map_audience(audience)
      Rails.logger.info "[Frontmatter] map_audience called with: #{audience.inspect}"
      result = case audience.to_s
      when "paid", "premium", "only_paid" then "paid"
      when "public", "free" then "everyone"
      else "everyone"
      end
      Rails.logger.info "[Frontmatter] map_audience result: #{result.inspect}"
      result
    end

    def format_date(date_str)
      return "" if date_str.nil? || date_str.empty?

      begin
        Time.parse(date_str).utc.iso8601(3)
      rescue ArgumentError
        date_str.to_s
      end
    end

    def resolve_image_path(post)
      return nil if post.cover_image.nil? || post.cover_image.empty?

      # Check if we have a local copy of the cover image
      cover_pattern = File.join(@site_root, "media", "images", "#{post.slug}-cover.*")
      cover_files = Dir.glob(cover_pattern)

      if cover_files.any?
        # Return relative path using /media/images/ pattern
        return "/media/images/#{File.basename(cover_files.first)}"
      end

      # Return the remote URL if no local copy
      post.cover_image.to_s
    end

    # Expected paths for media (used even when files don't exist yet)
    def expected_image_path(post)
      return nil unless post.cover_image.present? || post.type == "newsletter" || post.type == "podcast"

      # If a cover file already exists on disk, use its actual extension —
      # avoids writing `.jpg` to frontmatter when the real file is `.jpeg`
      # (or `.png`, `.webp`, etc.) due to a previous import or manual upload.
      existing = Dir.glob(File.join(@site_root, "media", "images", "#{post.slug}-cover.*")).first
      return "/media/images/#{File.basename(existing)}" if existing

      # Otherwise determine extension from the cover_image URL if available
      ext = ".jpg"
      if post.cover_image.present?
        parsed_ext = File.extname(URI.parse(post.cover_image).path).downcase
        ext = parsed_ext if parsed_ext.present? && parsed_ext.length > 1
      end

      "/media/images/#{post.slug}-cover#{ext}"
    rescue URI::InvalidURIError
      "/media/images/#{post.slug}-cover.jpg"
    end

    def expected_audio_path(post)
      return nil unless post.type == "podcast"
      "/media/audio/#{post.slug}.mp3"
    end

    def expected_video_path(post)
      return nil unless post.type == "video" || post.video_mux_playback_id.present?
      "/media/video/#{post.slug}.mp4"
    end

    def rss_item_for(post)
      return nil unless @rss_items
      @rss_items[post.id.to_s]
    end
  end
end
