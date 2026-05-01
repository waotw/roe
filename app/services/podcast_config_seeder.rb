require "yaml"
require "open-uri"

# Seeds an entry in site/system/features/podcast.yml from RSS channel
# data, and downloads the podcast artwork to /site/system/images/.
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
  ARTWORK_DIR = File.join(RoeSitePaths::SITE_PATH, "system/images").freeze

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

  def initialize(podcast_key, channel_data, mode: :create)
    @podcast_key = podcast_key.to_s
    @channel = (channel_data || {}).transform_keys(&:to_s)
    @mode = mode
  end

  def seed!
    config = load_config

    if config.key?(@podcast_key) && @mode == :create
      Rails.logger.info "[PodcastConfigSeeder] '#{@podcast_key}' already exists; not overwriting (mode: :create)"
      return :unchanged
    end

    artwork_filename = download_artwork

    config[@podcast_key] = build_entry(artwork_filename)

    write_config(config)
    SiteConfig.reload!("features/podcast") rescue nil  # safe no-op if cache hasn't been touched yet

    @mode == :create ? :created : :overwritten
  end

  private

  def load_config
    return {} unless File.exist?(PODCAST_YML)
    YAML.load_file(PODCAST_YML, permitted_classes: [Date, Time]) || {}
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

  def build_entry(artwork_filename)
    {
      # Strip trailing parenthesized suffixes — Substack private feeds get
      # auto-tagged with "(private feed for <email>)" which we don't want
      # showing up as the public-facing podcast title.
      "title"       => @channel["title"].to_s.sub(/\s*\([^)]*\)\s*\z/, "").strip,
      "description" => strip_html(@channel["description"]),
      "author"      => @channel["author"].to_s,
      "email"       => @channel["owner_email"].to_s,
      "category"    => @channel["category"].to_s,
      "subcategory" => @channel["subcategory"].to_s,
      "language"    => (@channel["language"] || "en").to_s,
      "copyright"   => @channel["copyright"].to_s,
      "explicit"    => parse_bool(@channel["explicit"]),
      "type"        => (@channel["type"].presence || "episodic").to_s,
      "artwork"     => artwork_filename.to_s,
      "link"        => @channel["link"].to_s
    }.reject { |_, v| v.respond_to?(:empty?) && v.empty? }
  end

  def parse_bool(value)
    %w[yes true 1].include?(value.to_s.downcase)
  end

  def strip_html(text)
    text.to_s.gsub(/<[^>]+>/, "").strip
  end

  # Downloads the podcast cover art to /site/system/images/<key>-artwork.<ext>.
  # Returns the filename only (matches existing convention in podcast.yml's
  # `artwork:` field — paths are resolved relative to /system/images/).
  # Returns "" on any failure so seeding still succeeds with no artwork.
  def download_artwork
    url = @channel["image_url"].to_s
    return "" if url.empty?

    ext = File.extname(URI.parse(url).path).downcase
    ext = ".jpg" if ext.empty?
    filename = "#{@podcast_key}-artwork#{ext}"
    dest = ARTWORK_DIR.join(filename)

    FileUtils.mkdir_p(ARTWORK_DIR)
    URI.open(url) { |io| File.binwrite(dest, io.read) }
    Rails.logger.info "[PodcastConfigSeeder] Downloaded artwork → #{dest}"

    filename
  rescue => e
    Rails.logger.warn "[PodcastConfigSeeder] Could not download artwork (#{e.class}: #{e.message}); leaving artwork blank"
    ""
  end
end
