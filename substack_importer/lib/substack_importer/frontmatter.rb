# frozen_string_literal: true

module SubstackImporter
  class Frontmatter
    def initialize(output_root:)
      @output_root = output_root
    end

    def build(post)
      fm = {}

      fm["post_id"] = post.id.to_s
      fm["slug"] = post.slug.to_s
      fm["title"] = post.title.to_s
      fm["subtitle"] = post.subtitle.to_s
      fm["date"] = format_date(post.date)
      fm["post_type"] = map_post_type(post.type)
      fm["status"] = post.is_published ? "published" : "draft"
      fm["audience"] = post.audience.to_s
      fm["podcast_url"] = post.podcast_url.to_s

      # Image: cover_image or first collected image
      image_path = resolve_image_path(post)
      fm["image"] = image_path.to_s

      # Podcast-specific fields
      if post.type == "podcast"
        fm["podcast_duration"] = post.podcast_duration if post.podcast_duration
        fm["podcast_episode_number"] = post.podcast_episode_number if post.podcast_episode_number
        fm["podcast_season_number"] = post.podcast_season_number if post.podcast_season_number
        fm["podcast_episode_type"] = post.podcast_episode_type.to_s if post.podcast_episode_type

        # Local media paths
        audio_path = resolve_audio_path(post)
        fm["audio"] = audio_path.to_s

        video_path = resolve_video_path(post)
        fm["video"] = video_path.to_s

        captions_path = resolve_captions_path(post)
        fm["captions"] = captions_path.to_s
      end

      fm
    end

    def to_yaml(post)
      fm = build(post)
      "---\n#{fm.map { |k, v| "#{k}: #{v.inspect}" }.join("\n")}\n---"
    end

    private

    def map_post_type(type)
      case type.to_s
      when "newsletter" then "article"
      when "podcast" then "podcast"
      when "page" then "page"
      else "article"
      end
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
      # Check for cover image downloaded locally
      cover_pattern = File.join(@output_root, "media", "images", "#{post.slug}-cover.*")
      cover_files = Dir.glob(cover_pattern)
      if cover_files.any?
        return "/media/images/#{File.basename(cover_files.first)}"
      end

      # Use remote URL
      post.cover_image.to_s
    end

    def resolve_audio_path(post)
      audio_file = File.join(@output_root, "media", "audio", "#{post.slug}.mp3")
      if File.exist?(audio_file)
        return "/media/audio/#{post.slug}.mp3"
      end

      ""
    end

    def resolve_video_path(post)
      video_file = File.join(@output_root, "media", "video", "#{post.slug}.mp4")
      if File.exist?(video_file)
        return "/media/video/#{post.slug}.mp4"
      end

      ""
    end

    def resolve_captions_path(post)
      captions_pattern = File.join(@output_root, "media", "captions", "#{post.slug}.*.vtt")
      captions_files = Dir.glob(captions_pattern)
      if captions_files.any?
        return "/media/captions/#{File.basename(captions_files.first)}"
      end

      ""
    end
  end
end
