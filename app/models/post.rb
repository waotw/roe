require "ostruct"

class Post < ApplicationRecord
  include ResolvesMediaAudience
  include HasAudience
  include HasMetadata
  include HasMarkdownExtensions
  include HasInlineFootnotes
  include TouchesMediaUsageIndex
  include IndexesMediaReferences

  scope :for_newsletter, -> {
    where("json_extract(metadata, '$.published_to') IN ('newsletter', 'both')")
  }
  scope :newsletter_ready, -> { published.for_newsletter }

  has_many :newsletter_sends, dependent: :destroy
  has_many :newsletter_recipients, through: :newsletter_sends, source: :member

  belongs_to :import, optional: true

  before_save :preserve_podcast_guid
  after_save :cleanup_podcast_yaml, if: :should_cleanup_yaml?

  # Public URL for the post on the live site (matches the `:post` route
  # in config/routes.rb → `posts/:url_name`).
  def public_url
    "/posts/#{url_name}"
  end

  # Every post type, and everything that makes one. This hash is the only place
  # a type is defined — to add one, add an entry here:
  #
  #   my_type: {
  #     label:       "My Type",        # shown in the picker
  #     description: "…",              # shown in the picker
  #     icon:        "📀",
  #     feature:     :my_feature_enabled?,  # optional — omit for always-on types
  #     metadata_fields: [                  # everything the editor offers
  #       { name: "thing", type: :text, required: true, label: "Thing",
  #         hint: "What goes here" },       # required: true → marked * and
  #     ],                                  # checked before publishing
  #     create_fields: %w[thing],           # the short list the NEW POST form asks
  #     scaffold: [ :player, :content ]     # markdown written into the new file
  #   }
  #
  # The three lists do different jobs:
  #   metadata_fields — SUGGESTED: offered in the editor. `required: true` marks
  #                     it with a * and gates publishing (missing_type_required_fields).
  #   create_fields   — the subset the NEW POST form asks for up front. Keep it
  #                     to what Roe needs to write a working post of this type.
  #                     Names resolve against this type's metadata_fields first,
  #                     then the core post fields in ContentMetadataSchema — so
  #                     `create_fields: %w[image]` works without redeclaring it.
  #   scaffold        — which blocks go in the body, `:content` marking where the
  #                     template body lands. See ContentScaffold.
  #
  # DECLARATION ORDER IS THE PICKER ORDER (see .post_type_options).
  #
  # One catch: a name used in metadata_fields must also exist in
  # ContentMetadataSchema, or the editor won't render a row for it. A guard test
  # (content_metadata_schema_test) fails with the field name if you forget.
  POST_TYPES = {
    article: {
      label: "Article",
      description: "Standard blog post",
      icon: "📝",
      metadata_fields: [],
      scaffold: [ :content ],
      create_fields: %w[subtitle image]
    },
    podcast: {
      label: "Podcast",
      description: "Podcast episode with RSS feed integration",
      icon: "🎙️",
      feature: :podcast_enabled?,
      metadata_fields: [
        { name: "audio", type: :text, required: true, label: "Audio File",
          hint: "Path to audio file (e.g., /media/audio/episode-1.mp3)" },
        { name: "video", type: :text, label: "Video File",
          hint: "Optional. Adds a video version of this episode (e.g., /media/video/episode-1.mp4). The site renders video when present; the RSS feed still uses the audio file." },
        { name: "duration", type: :text, required: true, label: "Duration",  # ← Mark as required
          hint: 'Auto-extracted from audio file, or manual (e.g., "3600" seconds or "01:00:00")' },
        { name: "podcast", type: :select, label: "Podcast",
          hint: "Which podcast feed does this episode belong to? Leave blank for a local-only episode that won't appear in any RSS feed.",
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
      ],
      # Player above the writing, episode list below — the order the ERB
      # episode page used. The list needs `podcast:` to know what to gather, so
      # it's only written once that's set.
      scaffold: [ :player, :content, :playlist ],
      # season comes before episode_number because it scopes it: episode 1 of
      # season 2 is a different episode 1.
      create_fields: %w[audio podcast season episode_number]
    },
    music: {
      label: "Music",
      description: "A music track — group into releases, distribute later",
      icon: "🎵",
      feature: :music_enabled?,
      metadata_fields: [
        { name: "audio", type: :text, required: true, label: "Audio File",
          hint: "Path to the audio file (e.g., /media/audio/summer/01-opening.flac)" },
        { name: "release", type: :select, label: "Release",
          hint: "The release this track belongs to. Defaults to singles.",
          options: -> { ReleaseConfig.release_keys } },
        { name: "track_number", type: :text, label: "Track Number", hint: "Optional" },
        { name: "duration", type: :text, label: "Duration", hint: 'Optional, e.g. "3:45"' },
        { name: "explicit", type: :select, label: "Explicit Content",
          hint: "Flags the track as explicit wherever that's carried.",
          options: [ "false", "true" ] },
        { name: "isrc", type: :text, label: "ISRC",
          hint: "The recording's code, e.g. QMZ123456789. Roe stores it with the track; nothing else reads it yet." },
        { name: "songwriters", type: :text, label: "Songwriters",
          hint: "Legal names, comma-separated — not stage names." },
        { name: "lyrics", type: :textarea, label: "Lyrics",
          hint: "The full text, if you want it kept with the track." }
      ],
      # Same shape as a podcast episode: the track's player, then the rest of
      # the release. Needs `release:` before the list can be written.
      scaffold: [ :player, :content, :playlist ],
      create_fields: %w[audio release track_number]
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
      ],
      scaffold: [ :player, :content ],
      create_fields: %w[audio]
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
      ],
      scaffold: [ :player, :content ],
      create_fields: %w[video]
    }
  }.freeze

  # Fields a writer expects to be unique, mapped to the fields that scope them.
  # A number only clashes inside its own context: episode 1 of season 2 doesn't
  # collide with episode 1 of season 1, or with episode 1 of another show — so
  # every scope field takes part in the comparison. `url_name` has no scope
  # because it IS the post's URL.
  #
  # Nothing here blocks a save: a conflict is surfaced as a warning and the
  # writer decides. See .conflicting_post.
  UNIQUE_FIELDS = {
    "url_name"       => [].freeze,
    "episode_number" => %w[podcast season].freeze,
    "track_number"   => %w[release].freeze,
    "chapter_number" => %w[audiobook].freeze
  }.freeze

  # The first other post already using this value, or nil. `scopes` is a hash of
  # scope field => value; `exclude_url_name` keeps a post from flagging itself.
  #
  # Everything is compared AS TEXT because YAML decides the type for us:
  # `episode_number: 1` stores an Integer and `episode_number: "1"` a String,
  # and in SQLite those don't compare equal — which silently hid every conflict
  # between a hand-written episode and one Roe created.
  def self.conflicting_post(field:, value:, scopes: {}, exclude_url_name: nil)
    field = field.to_s
    scope_fields = UNIQUE_FIELDS[field] # whitelist: names are interpolated below
    return nil unless scope_fields
    value = value.to_s.strip
    return nil if value.blank?

    rel = regular_posts.where("CAST(json_extract(metadata, '$.#{field}') AS TEXT) = ?", value)

    scopes = (scopes || {}).transform_keys(&:to_s)
    scope_fields.each do |scope_field|
      # Unset compares equal to unset, so two loose tracks with no release —
      # or two episodes with no season — still see each other's numbers.
      rel = rel.where(
        "IFNULL(CAST(json_extract(metadata, '$.#{scope_field}') AS TEXT), '') = ?",
        scopes[scope_field].to_s.strip
      )
    end

    if exclude_url_name.present?
      rel = rel.where("IFNULL(json_extract(metadata, '$.url_name'), '') != ?", exclude_url_name.to_s.strip)
    end

    rel.first
  end

  # Derived from the `feature:` key above, so a type is defined in exactly one
  # place. Types listed here only appear in the picker when their feature is on.
  # Post types whose published entries carry an immutable GUID. Both end up in
  # an RSS feed a podcatcher subscribes to, and a GUID is what it dedupes on —
  # change one and every subscriber sees that item as new.
  GUID_POST_TYPES = %w[podcast music].freeze

  FEATURE_GATED_TYPES = POST_TYPES.each_with_object({}) { |(type, config), out|
    out[type.to_s] = config[:feature] if config[:feature]
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

  # A post's audience, resolved the way every other default in Roe resolves:
  # its own value wins, then its show or release, then everyone.
  #
  # Overrides HasAudience#audience, which reads the post's own metadata only.
  # That was the whole of it until podcasts and releases gained an audience of
  # their own — after which a show marked paid protected its episodes' files
  # but left their pages readable and their feed entries unfiltered, because
  # every other gate still asked the post directly.
  #
  # An episode that sets its own audience overrides its show, which is what
  # lets the first three of a paid series be free.
  def audience
    own = metadata["audience"].to_s.strip
    return own if own.present?

    inherited_audience.presence || "everyone"
  end

  # Whether this post's FILES are protected. Same answer as #audience, kept as
  # its own name because the media index asks a narrower question and pages and
  # products answer it without any notion of inheritance.
  def media_audience
    audience == "paid" ? "paid" : "free"
  end


  # The audience of whatever this post belongs to, or nil when it belongs to
  # nothing that carries one.
  def inherited_audience
    case metadata["post_type"]
    when "podcast"
      key = metadata["podcast"].to_s.strip
      PodcastConfig.get(key).to_h["audience"].to_s.strip.presence if key.present?
    when "music"
      key = metadata["release"].to_s.strip
      ReleaseConfig.audience_for(key) if key.present?
    end
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

  # The picker's options, in POST_TYPES declaration order — that hash is where
  # the order is set. Legacy/custom types found in existing content follow,
  # alphabetically, so nothing a site already uses disappears from the picker.
  def self.post_type_options
    base = Rails.cache.fetch("post_type_options/v2", expires_in: 1.hour) do
      known = POST_TYPES.keys.map(&:to_s)
      known + (all_post_types - known).sort
    end

    # Hide a feature-gated type when its feature is off — but keep it if a post
    # already uses it, so an existing type never vanishes from the picker.
    # Filtered outside the cache so toggling a feature takes effect immediately.
    in_use = all_post_types
    base.reject do |type|
      gate = FEATURE_GATED_TYPES[type]
      gate && !SiteFeature.public_send(gate) && !in_use.include?(type)
    end
  end

  # Class method to get all unique tags efficiently
  def self.all_tags
    # Load all posts and extract tags from the already-parsed metadata hash.
    # Using json_extract + JSON.parse was unreliable because SQLite may return
    # the tags array in different forms depending on how it was stored.
    # Reading from post.metadata directly is always correct.
    all.flat_map { |p|
      tags = p.metadata["tags"]
      case tags
      when Array  then tags
      when String then tags.gsub(/[\[\]"']/, "").split(",").map(&:strip)
      else []
      end
    }.reject(&:blank?).uniq.sort
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
    # Resolve symlinks (notably /rails/site → /data/site on prod) so
    # this lookup matches records created via other paths into this
    # model. See RoeSitePaths.normalize for the why.
    absolute_path = RoeSitePaths.normalize(file_path)
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
      post = existing_posts.first_or_initialize(file_path: absolute_path)
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
      Rails.cache.delete("post_type_options/v2") if post.saved_changes.key?("metadata")
    rescue => e
      Rails.logger.error "Failed to save #{file_path}: #{e.message}"
      puts "\n  ✗ Error saving: #{File.basename(file_path)} - #{e.message}\n"
      return nil
    end

    has_warnings ? :warning : post
  end

  def self.remove_by_file_path(file_path)
    absolute_path = RoeSitePaths.normalize(file_path)
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

  # The full moment this post is dated to. Nil only when it has no date at all.
  #
  # #date returns a Date, so two posts on the same day had identical sort keys
  # — and Ruby's sort_by is not stable, so the order then came down to whatever
  # the database happened to return. A site built up over months and one
  # rebuilt in a single sync hand back different orders, which is how the same
  # collection came out differently on local and live. The times were in the
  # metadata the whole time and were being thrown away.
  #
  # Three accepted forms, all parsed the same way:
  #
  #   date: 2026-08-27                 → midnight
  #   date: 2026-08-14T13:45Z          → that instant (what a date picker writes)
  #   date: 2026-08-27, time: 13:45    → combined
  #
  # An explicit `time:` wins over a time inside `date:`, because writing it as
  # its own field is the more deliberate statement of the two.
  def timestamp
    day = date
    return nil unless day

    explicit = metadata["time"].to_s.strip
    if explicit.present?
      # A `time:` carrying a whole date is unusual but unambiguous — take it
      # as written rather than splicing a date onto it.
      return parse_timestamp(explicit) || day.to_time if explicit.match?(/\d{4}-\d{2}-\d{2}/)

      combined = parse_timestamp("#{day.iso8601}T#{explicit}")
      return combined if combined
    end

    parse_timestamp(metadata["date"]) || day.to_time
  end

  # Lenient on purpose: an unparseable value falls back to the date rather than
  # raising, matching how #date treats a bad string.
  def parse_timestamp(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
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

  # The short list of fields the NEW POST form asks for, in `create_fields`
  # order. Deliberately narrower than metadata_fields: only what Roe needs to
  # scaffold a working post of this type — the audio a player will play, the
  # podcast/release a track list will gather. Everything else is left to the
  # metadata editor afterwards.
  #
  # A name is resolved against this type's metadata_fields first, then against
  # the CORE post fields every type shares (ContentMetadataSchema) — so
  # `create_fields: %w[image]` works without copying `image` into the type,
  # which is the kind of duplication that lets the two drift apart.
  def self.create_fields_for_type(post_type)
    post_type = post_type.to_s
    type_config = POST_TYPES[post_type.to_sym]
    return [] unless type_config

    type_fields = type_config[:metadata_fields] || []
    # Pass the type through so a core field's `required` flag is resolved for
    # the type being built, not for the default.
    core = ContentMetadataSchema.fields_for("post", metadata: { "post_type" => post_type })

    Array(type_config[:create_fields]).filter_map do |name|
      name = name.to_s
      type_fields.find { |f| f[:name].to_s == name } ||
        ContentMetadataSchema.as_create_field(name, core[name])
    end
  end

  # Returns the subset of POST_TYPES required fields that are blank on this post.
  # Each entry is the original field hash from POST_TYPES (name/type/label/hint/options).
  def missing_type_required_fields
    required = self.class.required_fields_for_type(post_type)
    # Podcasts can be either-or on audio/video. When a video is set, the
    # audio "required" flag is downgraded to a soft notice (see
    # informational_notices) — the episode renders on the site as video
    # and won't appear in the podcast RSS feed until audio is added.
    if post_type == "podcast" && metadata["video"].to_s.strip.present?
      required = required.reject { |f| f[:name].to_s == "audio" }
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
    if post_type == "podcast" &&
       metadata["video"].to_s.strip.present? &&
       metadata["audio"].to_s.strip.blank?
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
    return nil unless str.start_with?("/media/")
    File.join(RoeSitePaths::SITE_PATH, str.delete_prefix("/")).to_s
  end

  # Per-request Set of every /media/... path that resolves to a real file.
  # Used by media_refs so admin views asking needs_attention? on many posts
  # pay for one directory glob, not one File.exist? per ref.
  def self.media_file_set
    Current.media_file_set ||= begin
      base = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "media"))
      files = Dir.glob(base.join("**/*"))
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
      exists = if path.start_with?("/media/")
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
    if SiteFeature.memberships_enabled? && metadata["audience"].to_s.strip.blank?
      gaps << "audience"
    end
    if SiteFeature.newsletters_enabled? && metadata["published_to"].to_s.strip.blank?
      gaps << "published_to"
    end
    gaps
  end

  # For podcast posts: returns the configured `podcast:` value when it
  # doesn't match any podcast key currently in podcast.yml (e.g. the user
  # renamed a podcast and old episode references are now orphaned).
  # Returns nil when the reference is valid or not applicable.
  def invalid_podcast_reference
    return nil unless post_type == "podcast"
    value = metadata["podcast"].to_s.strip
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
    publish_warnings?
  end

  # The same checks as needs_attention?, but without the published? guard — so
  # the admin can tell whether a DRAFT would publish clean (the bulk-publish
  # gate hides "Publish selected" when any chosen draft returns true here).
  def publish_warnings?
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

  # Class methods for filtering by type.
  #
  # These queried `$.type` for years; the key is `$.post_type`, so every one of
  # them returned nothing. Nothing called them, which is why it went unnoticed
  # — a helper that silently returns an empty set is indistinguishable from a
  # site with no podcasts. Delegating to by_type keeps one definition of where
  # the type lives.
  def self.articles = by_type("article")
  def self.music    = by_type("music")
  def self.podcasts = by_type("podcast")
  def self.images   = by_type("image")

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
    absolute_path = RoeSitePaths.normalize(file_path)
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
      ::OpenStruct.new(
        front_matter: metadata,
        content: body
      )
    else
      # No frontmatter found
      ::OpenStruct.new(
        front_matter: { "title" => File.basename(file_path, ".md") },
        content: content
      )
    end
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
    return unless GUID_POST_TYPES.include?(metadata["post_type"])
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
