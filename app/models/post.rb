class Post < ApplicationRecord
  include HasAudience
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes

  scope :for_newsletter, -> {
    where("json_extract(metadata, '$.published_to') IN ('newsletter', 'both')")
  }
  scope :newsletter_ready, -> { published.for_newsletter }

  has_many :media_references, dependent: :destroy
  has_many :media, through: :media_references, source: :medium
  has_many :newsletter_sends, dependent: :destroy
  has_many :newsletter_recipients, through: :newsletter_sends, source: :member

  belongs_to :import, optional: true

  before_save :preserve_podcast_guid
  after_save :cleanup_podcast_yaml, if: :should_cleanup_yaml?
  after_save :update_media_references

  # Post type definitions
  POST_TYPES = {
    article: {
      label: "Article",
      description: "Standard blog post",
      icon: "📝",
      metadata_fields: []
    },
    audio: {
      label: "Audio",
      description: "Article with featured audio player",
      icon: "🔊",
      metadata_fields: [
        { name: "audio", type: :text, required: true, label: "Audio File",
          hint: "Path to audio file (e.g., /media/audio/my-song.mp3)" },
        { name: "duration", type: :text, label: "Duration",
          hint: 'Optional, e.g., "12:34"' }
      ]
    },
    video: {
      label: "Video",
      description: "Article with featured video player",
      icon: "🎬",
      metadata_fields: [
        { name: "video", type: :text, required: true, label: "Video File",
          hint: "Path to video file (e.g., /media/video/my-video.mp4)" },
        { name: "duration", type: :text, label: "Duration",
          hint: 'Optional, e.g., "12:34"' }
      ]
    },
    podcast: {
      label: "Podcast",
      description: "Podcast episode with RSS feed integration",
      icon: "🎙️",
      metadata_fields: [
        { name: "audio", type: :text, required: true, label: "Audio File",
          hint: "Path to audio file (e.g., /media/audio/episode-1.mp3)" },
        { name: "video", type: :text, label: "Video File",
          hint: "Optional. Adds a video version of this episode (e.g., /media/video/episode-1.mp4). The site renders video when present; the RSS feed still uses the audio file." },
        { name: "duration", type: :text, required: true, label: "Duration",  # ← Mark as required
          hint: 'Auto-extracted from audio file, or manual (e.g., "3600" seconds or "01:00:00")' },
        { name: "podcast", type: :select, required: true, label: "Podcast",
          hint: "Which podcast feed does this episode belong to?",
          options: -> { PodcastConfig.podcast_keys } },
        { name: "author", type: :text, label: "Author",
          hint: "Override podcast default author for this episode" },
        { name: "explicit", type: :select, label: "Explicit Content",
          hint: "Does this episode contain explicit content?",
          options: [ "false", "true" ] },
        { name: "episode_number", type: :text, label: "Episode Number",
          hint: 'Episode number (e.g., "1")' },
        { name: "season", type: :text, label: "Season",
          hint: 'Season number (e.g., "1")' },
        { name: "episode_type", type: :select, label: "Episode Type",
          hint: "Type of episode",
          options: [ "full", "trailer", "bonus" ] },
        { name: "image", type: :text, label: "Episode Artwork",
          hint: "Override podcast artwork for this episode (e.g., /media/images/episode-1.jpg)" },
        { name: "subtitle", type: :text, label: "Subtitle",
          hint: "Short episode description" },
        { name: "captions", type: :text, label: "Captions/Transcript",
          hint: "Path to VTT captions file (e.g., /media/captions/episode-1.en.vtt)" }
      ]
    }
  }.freeze

  def audio
    metadata["audio"]
  end

  def video
    metadata["video"]
  end

  def duration
    metadata["duration"]
  end

  def captions
    metadata["captions"]
  end

  def has_media?
    post_type.in?([ "audio", "video" ]) && (audio.present? || video.present?)
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

  scope :for_newsletter, -> {
    where("json_extract(metadata, '$.published_to') IN ('newsletter', 'both')")
  }

  scope :newsletter_ready, -> {
    published.for_newsletter
  }

  def published_to
    metadata["published_to"] || "site"  # Default to 'site' if not set
  end

  def published_to_site?
    published_to == "site"
  end

  def published_to_newsletter?
    published_to == "newsletter"
  end

  def published_to_both?
    published_to == "both"
  end

  # Class method to get all unique post types efficiently
  def self.all_post_types
    pluck(Arel.sql("DISTINCT json_extract(metadata, '$.post_type')"))
      .compact
      .reject(&:blank?)
      .sort
  end

  def self.post_type_options
    Rails.cache.fetch("post_type_options", expires_in: 1.hour) do
      # Official types from POST_TYPES constant
      official_types = POST_TYPES.keys.map(&:to_s)

      # Types actually used in posts (for legacy/custom types)
      discovered_types = all_post_types

      # Merge, dedupe, and sort
      (official_types + discovered_types).uniq.sort
    end
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

  def tags
    tag_data = metadata["tags"]

    case tag_data
    when Array
      # Filter out blank entries AND the literal string "[]"
      tag_data.reject { |tag| tag.blank? || tag.to_s.strip == "[]" }
    when String
      normalized = tag_data.strip

      # Handle empty or "[]" strings
      return [] if normalized.empty? || normalized == "[]"

      # Try parsing as JSON array first
      if normalized.start_with?("[") && normalized.end_with?("]")
        begin
          parsed = JSON.parse(normalized)
          return parsed.is_a?(Array) ? parsed.reject { |t| t.blank? || t == "[]" } : []
        rescue JSON::ParserError
          return [] if normalized == "[]"
        end
      end

      # Comma-separated tags
      if normalized.include?(",")
        return normalized.split(",").map(&:strip).reject(&:blank?)
      end

      # Single tag
      [ normalized ]
    when nil
      []
    else
      []
    end
  end

  def self.create_or_update_from_file(file_path)
    absolute_path = File.expand_path(file_path)
    has_warnings = false
    yaml_parse_error = nil

    begin
      parsed = FrontMatterParser::Parser.parse_file(file_path)
    rescue => e
      # First attempt: Try to fix GUID specifically
      if fix_guid_in_file(file_path)
        # Try parsing again after GUID fix
        begin
          parsed = FrontMatterParser::Parser.parse_file(file_path)
          puts "\n  ✓ Auto-fixed malformed GUID in #{File.basename(file_path)}\n"
          yaml_parse_error = nil
        rescue => e2
          # Still broken after GUID fix - use fallback
          Rails.logger.error "Failed to parse #{file_path} even after GUID fix: #{e2.message}"
          puts "\n  ⚠️  YAML parsing error: #{File.basename(file_path)}"
          puts "     #{e2.message}"
          puts "     Post saved with broken metadata - edit in admin to fix\n"

          yaml_parse_error = e2.message
          parsed = extract_broken_frontmatter(file_path)
        end
      else
        # GUID fix didn't apply or failed - use fallback
        Rails.logger.error "Failed to parse #{file_path}: #{e.message}"
        puts "\n  ⚠️  YAML parsing error: #{File.basename(file_path)}"
        puts "     #{e.message}"
        puts "     Post saved with broken metadata - edit in admin to fix\n"

        yaml_parse_error = e.message
        parsed = extract_broken_frontmatter(file_path)
      end
    end

    # Rest of validation (skip for broken YAML)
    unless yaml_parse_error
      if parsed.front_matter["date"].present?
        begin
          Date.parse(parsed.front_matter["date"].to_s)
        rescue ArgumentError, TypeError => e
          Rails.logger.error "Invalid date in #{file_path}: #{parsed.front_matter['date']}"
          puts "\n  ✗ Invalid date: #{File.basename(file_path)} - '#{parsed.front_matter['date']}' is not a valid date\n"
          return nil
        end
      end

      if parsed.front_matter["status"] == "published"
        if parsed.front_matter["title"].blank?
          Rails.logger.warn "Published post missing title: #{file_path}"
          puts "\n  ⚠ Missing title: #{File.basename(file_path)}"
          has_warnings = true
        end

        if parsed.front_matter["date"].blank?
          Rails.logger.warn "Published post missing date: #{file_path}"
          puts "  ⚠ Missing date: #{File.basename(file_path)}\n"
          has_warnings = true
        end
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
    if parsed.front_matter["tags"].is_a?(String)
      parsed.front_matter["tags"] = parsed.front_matter["tags"]
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
    end

    post.metadata = parsed.front_matter
    post.content = parsed.content

    # Mark if YAML was broken
    if yaml_parse_error
      post.metadata["_yaml_parse_error"] = yaml_parse_error
    end

    begin
      post.save!

      # Invalidate post_type cache if metadata changed
      Rails.cache.delete("post_type_options") if post.saved_changes.key?("metadata")
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

  def self.required_fields_for_type(post_type)
    type_config = POST_TYPES[post_type.to_s.to_sym]
    return [] unless type_config
    (type_config[:metadata_fields] || []).select { |f| f[:required] }
  end

  # Returns the subset of POST_TYPES required fields that are blank on this post.
  # Each entry is the original field hash from POST_TYPES (name/type/label/hint/options).
  def missing_type_required_fields
    required = self.class.required_fields_for_type(post_type)
    # Podcasts can be either-or on audio/video. When a video is set, the
    # audio "required" flag is downgraded to a soft notice (see
    # informational_notices) — the episode renders on the site as video
    # and won't appear in the podcast RSS feed until audio is added.
    if post_type == 'podcast' && metadata['video'].to_s.strip.present?
      required = required.reject { |f| f[:name].to_s == 'audio' }
    end
    required.reject do |field|
      metadata[field[:name].to_s].to_s.strip.present?
    end
  end

  # Soft, non-blocking notices for the admin editor. Distinct from
  # missing_type_required_fields and needs_attention? — these are FYIs
  # that don't block save or publish, but give the user useful context
  # about how the post will behave.
  def informational_notices
    notes = []
    if post_type == 'podcast' &&
       metadata['video'].to_s.strip.present? &&
       metadata['audio'].to_s.strip.blank?
      notes << "This episode will play on the site as video, but it won't appear in the podcast RSS feed until you add an audio file."
    end
    notes
  end

  # Metadata fields that point at files under site/media/…
  MEDIA_FIELDS = %w[audio video image captions].freeze

  # Resolves a /media/... style path to an absolute filesystem path under site/.
  # Returns nil for blank or non-/media paths (we only validate local refs).
  def self.resolve_media_path(path)
    str = path.to_s.strip
    return nil if str.empty?
    return nil unless str.start_with?('/media/')
    Rails.root.join('site', str.delete_prefix('/')).to_s
  end

  # Per-request Set of every /media/... path that resolves to a real file.
  # Used by media_refs so admin views asking needs_attention? on many posts
  # pay for one directory glob, not one File.exist? per ref.
  def self.media_file_set
    Current.media_file_set ||= begin
      base = Rails.root.join('site/media')
      files = Dir.glob(base.join('**/*'))
                 .select { |f| File.file?(f) }
                 .map { |f| "/media/" + Pathname.new(f).relative_path_from(base).to_s }
      Set.new(files)
    end
  end

  # Returns [{ field:, path:, exists: }] for every media field this post sets.
  def media_refs
    MEDIA_FIELDS.filter_map do |field|
      path = metadata[field].to_s.strip
      next if path.empty?

      # Paths that don't start with /media/ aren't checkable — treat as present.
      exists = if path.start_with?('/media/')
                 self.class.media_file_set.include?(path)
               else
                 true
               end
      { field: field, path: path, exists: exists }
    end
  end

  def missing_media_refs
    media_refs.reject { |ref| ref[:exists] }
  end

  # Returns names of site-gated metadata fields that are blank but should
  # be set on a published post. Mirrors the publish modal's prompts so
  # the admin warning catches file-edit-bypass cases.
  def missing_site_gated_fields
    gaps = []
    if SiteFeature.payments_enabled? && metadata['audience'].to_s.strip.blank?
      gaps << 'audience'
    end
    if SiteFeature.newsletters_enabled? && metadata['published_to'].to_s.strip.blank?
      gaps << 'published_to'
    end
    gaps
  end

  # For podcast posts: returns the configured `podcast:` value when it
  # doesn't match any podcast key currently in podcast.yml (e.g. the user
  # renamed a podcast and old episode references are now orphaned).
  # Returns nil when the reference is valid or not applicable.
  def invalid_podcast_reference
    return nil unless post_type == 'podcast'
    value = metadata['podcast'].to_s.strip
    return nil if value.empty?
    return nil if PodcastConfig.podcast_keys.include?(value)
    value
  end

  # A published post "needs attention" if it's missing required fields for its
  # type, has media references pointing at files that don't exist on disk,
  # is missing site-gated fields (audience / published_to) that the
  # publish modal would have prompted for, or references a podcast key
  # that no longer exists in podcast.yml (orphaned reference).
  # Used to surface warnings in the admin UI without blocking save.
  def needs_attention?
    return false unless published?
    missing_type_required_fields.any? ||
      missing_media_refs.any? ||
      missing_site_gated_fields.any? ||
      !invalid_podcast_reference.nil?
  end

  def type
    metadata["type"] || "article"
  end

  def send_as_newsletter?
    published_to_newsletter? || published_to_both?
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

  def self.feed_posts
    published.where("file_path NOT LIKE ?", "%site/docs/%")
  end

  def filename
    File.basename(file_path, ".md") if file_path.present?
  end

  private

  def self.fix_guid_in_file(file_path)
    return false unless File.exist?(file_path)

    content = File.read(file_path)

    # Check if file has frontmatter
    return false unless content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)/m

    frontmatter = $1
    body = $2

    # Check if there's a guid line (even malformed)
    return false unless frontmatter =~ /^\s*guid\s*:/m

    # Find existing post to get the authoritative GUID
    absolute_path = File.expand_path(file_path)
    post = find_by(file_path: absolute_path)

    return false unless post&.metadata&.dig("guid").present?

    correct_guid = post.metadata["guid"]

    # Remove ALL guid lines (in case there are duplicates or malformed ones)
    fixed_frontmatter = frontmatter.lines.reject { |line| line =~ /^\s*guid\s*:/ }.join

    # Add correct GUID at the end
    fixed_frontmatter = fixed_frontmatter.rstrip + "\nguid: \"#{correct_guid}\"\n"

    # Write fixed content back
    fixed_content = "---\n#{fixed_frontmatter}---\n#{body}"
    File.write(file_path, fixed_content)

    Rails.logger.info "🔧 Auto-fixed malformed GUID in #{File.basename(file_path)}"
    true
  rescue => e
    Rails.logger.error "Failed to auto-fix GUID: #{e.message}"
    false
  end

  def self.extract_broken_frontmatter(file_path)
    content = File.read(file_path)

    # Try to extract frontmatter block even if YAML is broken
    if content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)/m
      raw_yaml = $1
      body = $2

      # Parse line by line, skipping broken lines
      metadata = {}
      raw_yaml.each_line do |line|
        next if line.strip.empty?

        if line =~ /^(\w+):\s*(.*)$/
          key = $1
          value = $2.strip
          # Remove quotes if present and complete
          if (value.start_with?('"') && value.end_with?('"')) ||
             (value.start_with?("'") && value.end_with?("'"))
            value = value[1..-2]
          end
          metadata[key] = value
        end
      end

      # Create a parsed-like object
      OpenStruct.new(
        front_matter: metadata,
        content: body
      )
    else
      # No frontmatter found
      OpenStruct.new(
        front_matter: { "title" => File.basename(file_path, ".md") },
        content: content
      )
    end
  end

  def update_media_references
    # Extract media paths from content
    media_paths = extract_media_paths

    # Find matching Medium records
    referenced_media = Medium.where(file_path: media_paths)

    # Replace all references for this post
    self.media_references.destroy_all
    referenced_media.each do |medium|
      self.media_references.create(medium: medium)
    end
  end

  def extract_media_paths
    paths = []

    # Extract from content
    if content.present?
      paths += content.scan(/!\[.*?\]\((\/media\/[^\)]+)\)/).flatten
      paths += content.scan(/<img[^>]+src=["'](\/media\/[^"']+)["']/).flatten
      paths += content.scan(/<(?:audio|video)[^>]+src=["'](\/media\/[^"']+)["']/).flatten
    end

    # Extract from metadata fields (image, audio, video, thumbnail, etc.)
    if metadata.present?
      [ "image", "audio", "video", "thumbnail", "cover", "poster" ].each do |field|
        value = metadata[field]
        if value.is_a?(String) && value.start_with?("/media/")
          paths << value
        end
      end
    end

    paths.uniq
  end

  def should_cleanup_yaml?
    metadata["post_type"] == "podcast" && metadata["status"] == "published"
  end

  def cleanup_podcast_yaml
    return unless File.exist?(file_path)
    return unless metadata["guid"].present? # Only run if post has a GUID

    begin
      content = File.read(file_path)

      # Check if GUID in file matches database
      if content =~ /\A---\s*\n(.*?)\n---\s*\n/m
        frontmatter = $1

        # Extract current GUID from file (if any)
        file_guid = nil
        if frontmatter =~ /^\s*guid\s*:\s*"?([^"\n]+)"?\s*$/
          file_guid = $1.strip
        end

        # Only rewrite if GUID is wrong or missing
        db_guid = metadata["guid"]

        if file_guid != db_guid
          # Remove all existing guid lines
          cleaned_frontmatter = frontmatter.lines.reject { |line| line =~ /^\s*guid\s*:/ }.join

          # Add correct GUID at the end
          cleaned_frontmatter = cleaned_frontmatter.rstrip + "\nguid: \"#{db_guid}\"\n"

          # Reconstruct file
          body = content.sub(/\A---\s*\n.*?\n---\s*\n/m, "")
          new_content = "---\n#{cleaned_frontmatter}---\n#{body}"

          File.write(file_path, new_content)
          Rails.logger.info "🔒 Fixed GUID for '#{metadata['title']}'"
        end
      end

    rescue => e
      Rails.logger.error "❌ Failed to fix GUID for '#{metadata['title']}': #{e.message}"
    end
  end

  def preserve_podcast_guid
    return unless metadata["post_type"] == "podcast"
    return unless metadata["status"] == "published"

    # Check if GUID is being removed or changed
    if metadata_changed? && metadata_was.present?
      old_guid = metadata_was["guid"]
      new_guid = metadata["guid"]

      # If GUID existed and is now missing/different, restore it
      if old_guid.present? && (new_guid.blank? || new_guid != old_guid)
        self.metadata = metadata.merge("guid" => old_guid)
        Rails.logger.warn "🔒 Prevented GUID modification for '#{metadata['title']}' (restored: #{old_guid})"
      end
    end
  end
end
