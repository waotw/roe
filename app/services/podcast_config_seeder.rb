require "yaml"
require "open-uri"

# Seeds an entry in site/system/features/podcast.yml from RSS channel
# data, and downloads the podcast artwork to /site/system/assets/images/
# — the canonical location for system-level images, the same place the
# admin "Manage GLOBAL IMAGES" UI uploads to.
#
# Two modes:
# - mode: :create  — only adds the entry if missing (default; safe for
#   the Substack importer auto-seeding flow so we don't clobber user
#   customizations on re-import).
# - mode: :overwrite — replaces the entry. Used by the standalone admin
#   "Seed from RSS feed" button where the user is explicitly asking
#   for the podcast.yml entry to be (re)generated.
class PodcastConfigSeeder
  PODCAST_YML = File.join(RoeSitePaths::SITE_PATH, "system/features/podcast.yml").freeze
  ARTWORK_DIR = File.join(RoeSitePaths::SITE_PATH, "system/assets/images").freeze

  # Single source of truth for podcast-key derivation. Both the Substack
  # importer (deriving the `podcast:` field for episodes) and the admin
  # "Seed from RSS feed" controller (deriving the podcast.yml top-level
  # key) MUST produce the same string for the same RSS title — otherwise
  # episodes get a `podcast:` reference that doesn't resolve.
  #
  # Strips trailing parenthesized suffixes (Substack appends "(private
  # feed for <email>)" to private titles) so the key reflects the show's
  # actual name.
  def self.derive_key(title)
    title.to_s.sub(/\s*\([^)]*\)\s*\z/, "").strip.parameterize
  end

  def initialize(podcast_key, channel_data, mode: :create, subscribe_links: {})
    @podcast_key = podcast_key.to_s
    @channel = (channel_data || {}).transform_keys(&:to_s)
    @mode = mode
    # Extra subscribe-app URLs to fold into the entry (e.g. Apple + Overcast
    # derived from an Apple Podcasts seed source). Kept out of build_entry's
    # canonical set since they're not iTunes-spec feed fields.
    @subscribe_links = (subscribe_links || {}).transform_keys(&:to_s)
  end

  def seed!
    config = load_config

    if config.key?(@podcast_key) && @mode == :create
      Rails.logger.info "[PodcastConfigSeeder] '#{@podcast_key}' already exists; not overwriting (mode: :create)"
      return :unchanged
    end

    artwork_filename = download_artwork

    # Merge onto any existing entry so subscribe links and other non-canonical
    # fields the user set aren't wiped on re-seed. Feed-derived canonical
    # fields and any derived subscribe links take precedence.
    existing = (config[@podcast_key] || {}).transform_keys(&:to_s)
    config[@podcast_key] = existing.merge(build_entry(artwork_filename))

    write_config(config)
    SiteConfig.reload!("features/podcast") rescue nil  # safe no-op if cache hasn't been touched yet

    @mode == :create ? :created : :overwritten
  end

  private

  def load_config
    return {} unless File.exist?(PODCAST_YML)
    YAML.load_file(PODCAST_YML, permitted_classes: [ Date, Time ]) || {}
  rescue Psych::SyntaxError => e
    Rails.logger.error "[PodcastConfigSeeder] podcast.yml has invalid YAML: #{e.message}; refusing to overwrite"
    raise
  end

  def write_config(config)
    FileUtils.mkdir_p(File.dirname(PODCAST_YML))
    # Strip the leading "---\n" document marker — podcast.yml is a single
    # document so the marker is just visual noise (and the form-based YAML
    # editor saves without it, so this keeps the file format consistent
    # whether the user seeds or hand-edits).
    yaml = config.to_yaml.sub(/\A---\s*\n/, "")
    File.write(PODCAST_YML, yaml)
  end

  # Build a canonical-shape entry from feed channel data. All
  # PodcastConfig::CANONICAL_FIELDS are always emitted, blank when
  # the source provided nothing — they become visible "fill me in"
  # prompts in the admin editor, which is what we want for iTunes
  # spec compliance.
  def build_entry(artwork_filename)
    extracted = {
      # Strip trailing parenthesized suffixes — Substack private feeds get
      # auto-tagged with "(private feed for <email>)" which we don't want
      # showing up as the public-facing podcast title.
      "title"       => @channel["title"].to_s.sub(/\s*\([^)]*\)\s*\z/, "").strip,
      "description" => strip_html(@channel["description"]),
      "author"      => @channel["author"].to_s,
      "email"       => @channel["owner_email"].to_s,
      # Owner name falls back to author — that's what RSS feeds with
      # only one of the two conventionally mean. Atom feeds typically
      # populate author/name into both via the parser.
      "owner_name"  => (@channel["owner_name"].presence || @channel["author"]).to_s,
      "category"    => @channel["category"].to_s,
      "subcategory" => @channel["subcategory"].to_s,
      "language"    => (@channel["language"].presence || "en").to_s,
      "copyright"   => @channel["copyright"].to_s,
      "explicit"    => parse_bool(@channel["explicit"]).to_s,
      "type"        => (@channel["type"].presence || "episodic").to_s,
      "artwork"     => artwork_filename.to_s,
      "link"        => @channel["link"].to_s
    }

    entry = PodcastConfig::CANONICAL_FIELDS.each_with_object({}) do |field, e|
      e[field] = extracted.fetch(field, PodcastConfig::FIELD_DEFAULTS.fetch(field, ""))
    end
    # Fold in any derived subscribe links (Apple / Overcast from an Apple source).
    @subscribe_links.each { |k, v| entry[k] = v if v.present? }
    entry
  end

  # Public entry points for callers that need the seeder's behaviour
  # piecemeal (the "Enable Podcasts" modal uses these so it can
  # respect form edits on top of feed-derived values).
  public

  # Class-method wrapper around the instance's download_artwork so a
  # caller can download artwork without going through a full seed!.
  # Returns the filename written to /site/system/assets/images/ (or ""
  # on any failure — never raises).
  def self.fetch_artwork(podcast_key, image_url)
    return "" if image_url.to_s.empty?
    new(podcast_key, { "image_url" => image_url }, mode: :overwrite).send(:download_artwork)
  end

  # Build the canonical entry hash from feed channel data WITHOUT
  # writing or downloading. Used by the "Fill from feed" preview in
  # the enable modal — preview shouldn't have side effects.
  def self.entry_from_channel(channel, artwork_filename: "")
    new("preview", (channel || {}).transform_keys(&:to_s), mode: :overwrite)
      .send(:build_entry, artwork_filename)
  end

  private

  def parse_bool(value)
    %w[yes true 1].include?(value.to_s.downcase)
  end

  def strip_html(text)
    text.to_s.gsub(/<[^>]+>/, "").strip
  end

  # Downloads the podcast cover art to /site/system/assets/images/<key>-artwork.<ext>.
  # Returns the filename only (matches existing convention in podcast.yml's
  # `artwork:` field — paths are resolved relative to /system/images/,
  # which the System::ImagesController serves from /site/system/assets/images/).
  # Returns "" on any failure so seeding still succeeds with no artwork.
  def download_artwork
    url = @channel["image_url"].to_s
    return "" if url.empty?

    ext = File.extname(URI.parse(url).path).downcase
    ext = ".jpg" if ext.empty?
    filename = "#{@podcast_key}-artwork#{ext}"
    # ARTWORK_DIR is a String (File.join), so use File.join here — String has
    # no #join, and the previous ARTWORK_DIR.join(filename) raised
    # NoMethodError that the rescue below swallowed, silently skipping the
    # download and leaving artwork blank.
    dest = File.join(ARTWORK_DIR, filename)

    FileUtils.mkdir_p(ARTWORK_DIR)
    URI.open(url) { |io| File.binwrite(dest, io.read) }
    Rails.logger.info "[PodcastConfigSeeder] Downloaded artwork → #{dest}"

    filename
  rescue => e
    Rails.logger.warn "[PodcastConfigSeeder] Could not download artwork (#{e.class}: #{e.message}); leaving artwork blank"
    ""
  end
end
