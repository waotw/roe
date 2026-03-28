class Post < ApplicationRecord
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes

  # Post type definitions
  POST_TYPES = {
    article: {
      label: "Article",
      description: "Essay, blog post, newsletter…",
      icon: "📝",
      metadata_fields: []
    },
    audio: {
      label: "Audio",
      description: "Article with featured audio player",
      icon: "🔊",
      metadata_fields: [
        { name: 'audio_file', type: :text, required: true, label: 'Audio File',
          hint: 'Path to audio file (e.g., /media/my-song.mp3)' },
        { name: 'duration', type: :text, label: 'Duration',
          hint: 'Optional, e.g., "12:34"' }
      ]
    },
    video: {
      label: "Video",
      description: "Article with featured video player",
      icon: "🎬",
      metadata_fields: [
        { name: 'video_file', type: :text, required: true, label: 'Video File',
          hint: 'Path to video file (e.g., /media/my-video.mp4)' },
        { name: 'duration', type: :text, label: 'Duration',
          hint: 'Optional, e.g., "12:34"' }
      ]
    }
  }.freeze

  def audio_file
    metadata['audio_file']
  end

  def video_file
    metadata['video_file']
  end

  def duration
    metadata['duration']
  end

  def has_media?
    post_type.in?(['audio', 'video']) && (audio_file.present? || video_file.present?)
  end

  # Additional post-specific scopes
  scope :by_type, ->(post_type) {
    where("json_extract(metadata, '$.post_type') = ?", post_type)
  }

  scope :regular_posts, -> {
    where("file_path NOT LIKE ?", "%site/docs/%")
  }

  scope :public_posts, -> {
    public_items.regular_posts
  }

  scope :feed_posts, -> {
    published.regular_posts
  }

  # Class method to get all unique post types efficiently
  def self.all_post_types
    pluck(Arel.sql("DISTINCT json_extract(metadata, '$.post_type')"))
      .compact
      .reject(&:blank?)
      .sort
  end

  # Class method to get all unique tags efficiently
  def self.all_tags
    # Get all tag arrays, flatten, and uniquify
    select("json_extract(metadata, '$.tags') as tag_json")
      .where("json_extract(metadata, '$.tags') IS NOT NULL")
      .map { |p| JSON.parse(p.tag_json) rescue [] }
      .flatten
      .uniq
      .compact
      .sort
  end

  def self.create_or_update_from_file(file_path)
    absolute_path = File.expand_path(file_path)
    has_warnings = false

    begin
      parsed = FrontMatterParser::Parser.parse_file(file_path)
    rescue => e
      Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
      puts "\n  ✗ Error parsing: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    if parsed.front_matter['date'].present?
      begin
        Date.parse(parsed.front_matter['date'].to_s)
      rescue ArgumentError, TypeError => e
        Rails.logger.error "Invalid date in #{file_path}: #{parsed.front_matter['date']}"
        puts "\n  ✗ Invalid date: #{File.basename(file_path)} - '#{parsed.front_matter['date']}' is not a valid date\n"
        return nil
      end
    end

    if parsed.front_matter['status'] == 'published'
      if parsed.front_matter['title'].blank?
        Rails.logger.warn "Published post missing title: #{file_path}"
        puts "\n  ⚠ Missing title: #{File.basename(file_path)}"
        has_warnings = true
      end

      if parsed.front_matter['date'].blank?
        Rails.logger.warn "Published post missing date: #{file_path}"
        puts "  ⚠ Missing date: #{File.basename(file_path)}\n"
        has_warnings = true
      end
    end

    existing_posts = where(file_path: absolute_path)

    if existing_posts.count > 1
      Rails.logger.warn "Found #{existing_posts.count} posts for #{file_path}, cleaning up duplicates"
      post = existing_posts.order(created_at: :desc).first
      existing_posts.where.not(id: post.id).destroy_all
      puts "  ℹ Removed #{existing_posts.count - 1} duplicate(s) for #{File.basename(file_path)}"
    else
      post = existing_posts.first_or_initialize
    end

    # Convert comma-separated tags to array (preserves -tag syntax)
    if parsed.front_matter['tags'].is_a?(String)
      parsed.front_matter['tags'] = parsed.front_matter['tags']
        .split(',')
        .map(&:strip)
        .reject(&:blank?)
    end

    post.metadata = parsed.front_matter
    post.content = parsed.content

    begin
      post.save!
    rescue => e
      Rails.logger.error "Failed to save #{file_path}: #{e.message}"
      puts "\n  ✗ Error saving: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    has_warnings ? :warning : post
  end

  def self.remove_by_file_path(file_path)
    absolute_path = File.expand_path(file_path)
    find_by(file_path: absolute_path)&.destroy
  end

  # def to_html
  #   Kramdown::Document.new(
  #     content,
  #     footnote_backlink: '↩'
  #   ).to_html
  # end

  def validate_for_display
    errors = []

    if published?
      errors << "Published posts must have a title" if metadata["title"].blank?
      errors << "Published posts must have a date" if metadata["date"].blank?
    end

    errors
  end

  def date
    date_value = metadata["date"]
    return nil if date_value.blank?
    return date_value if date_value.is_a?(Date)

    begin
      Date.parse(date_value.to_s)
    rescue ArgumentError, TypeError
      File.mtime(file_path).to_date
    end
  end

  def author
    metadata["author"]
  end

  # Post status methods
  def unlisted?
    status == "unlisted"
  end

  # Type methods
  def self.types
    pluck(Arel.sql("DISTINCT json_extract(metadata, '$.type')"))
      .compact
      .sort
  end

  # replaced by scope at top of file.
  # def self.by_type(type)
  #   where("json_extract(metadata, '$.type') = ?", type)
  # end

  def post_type
    metadata["post_type"] || "article"  # Default to article if not specified
  end

  def type
    metadata["type"] || "article"
  end

  # Class methods for filtering by type
  def self.articles
    where("json_extract(metadata, '$.type') = ?", "article")
  end

  def self.music
    where("json_extract(metadata, '$.type') = ?", "music")
  end

  def self.podcasts
    where("json_extract(metadata, '$.type') = ?", "podcast")
  end

  def self.images
    where("json_extract(metadata, '$.type') = ?", "image")
  end

  # Class methods for filtering by status
  def self.unlisted
    where("json_extract(metadata, '$.status') = ?", "unlisted")
  end

  # def self.documentation
  #   where("file_path LIKE ?", "%content/docs/%")
  # end

  def self.public_documentation
    where("json_extract(metadata, '$.status') IN ('published', 'unlisted')")
  end

  def self.regular_posts
    where("file_path NOT LIKE ?", "%site/docs/%")
  end

  def self.public_posts
    where("json_extract(metadata, '$.status') = ?", "published")
      .where("file_path NOT LIKE ?", "%site/docs/%")
  end

  def self.feed_posts
    published.where("file_path NOT LIKE ?", "%site/docs/%")
  end
end
