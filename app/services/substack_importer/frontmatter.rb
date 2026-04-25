# frozen_string_literal: true

module SubstackImporter
  class Frontmatter
    def initialize(site_root:)
      @site_root = site_root
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

      # Image: always add expected path (even if file doesn't exist yet)
      # This allows missing media manager to verify/fix later
      image_path = local_media[:cover_image] || expected_image_path(post) || resolve_image_path(post)
      fm["image"] = image_path if image_path.present?

      # Podcast-specific fields
      if post.type == "podcast"
        fm["podcast_duration"] = post.podcast_duration if post.podcast_duration
        fm["podcast_episode_number"] = post.podcast_episode_number if post.podcast_episode_number
        fm["podcast_season_number"] = post.podcast_season_number if post.podcast_season_number
        fm["podcast_episode_type"] = post.podcast_episode_type.to_s if post.podcast_episode_type

        # Audio: write the expected path only when audio was actually attempted
        # (i.e., Substack reported a podcast_url). For a video-only podcast,
        # podcast_url is empty and we skip the field entirely so it doesn't
        # appear as a phantom "missing media" warning in admin.
        audio_path = local_media[:audio]
        audio_path ||= expected_audio_path(post) if post.podcast_url.present?
        fm["audio"] = audio_path if audio_path.present?
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

      # Determine extension from cover_image URL if available
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
  end
end
