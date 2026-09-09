# frozen_string_literal: true

# Builds a reverse index of which content and config files reference each
# media file under /media/. Powers the "Used in" backlinks on the media
# browse page across every source — posts, pages, documentation, products,
# and config YAML (e.g. the site logo in site.yml) — not just posts.
#
# Usage:
#   index = MediaUsageIndex.fetch
#   index["/media/images/logo.svg"]  # => [ { kind:, label:, url:, global: } ]
#
# The index is computed by scanning DB-backed content (content + metadata)
# and a registry of config files. Results are cached once the media library
# grows past CACHE_THRESHOLD; below it we just rebuild each call (cheap, and
# avoids stale-cache surprises on small sites). Mutating media, content, or
# config calls MediaUsageIndex.invalidate! to drop the cache.
class MediaUsageIndex
  include Rails.application.routes.url_helpers

  CACHE_KEY = "media_usage_index/v1"
  # Only cache once scanning is worth avoiding on every browse load.
  CACHE_THRESHOLD = 200

  # Whether config files are scanned so config-referenced media (e.g. the
  # site logo) gets a backlink in the normal "Used in" badge.
  CONFIG_BACKLINKS_ENABLED = true

  # Whether the standalone "Global" filter tab is shown on the browse page.
  # Deferred for now — config backlinks appear inline in the badge and the
  # System Images link covers global-image management, so the tab isn't
  # needed yet. Flip to true to bring it back (it still only shows when
  # global media actually exists).
  GLOBAL_TAB_ENABLED = false

  # Any /media/... reference: path-safe chars only, so trailing quotes,
  # parens, or whitespace in markdown/HTML/YAML don't get captured.
  MEDIA_PATH = %r{/media/[\w./\-]+}

  # Compact per-source labels shown next to each backlink.
  KIND_LABELS = {
    "post" => "post",
    "page" => "page",
    "documentation" => "doc",
    "product" => "prod.",
    "config" => "config"
  }.freeze

  # DB-backed content types to scan. Each is an ActiveRecord model exposing
  # #content, #metadata, and #file_path, plus an edit-path helper. The
  # editor highlights the referencing line via ?highlight=<path>.
  CONTENT_SOURCES = [
    { model: "Post",          kind: "post",          path_helper: :edit_admin_post_path },
    { model: "Page",          kind: "page",          path_helper: :edit_admin_page_path },
    { model: "Documentation", kind: "documentation", path_helper: :edit_admin_documentation_path },
    { model: "Product",       kind: "product",       path_helper: :edit_admin_product_path }
  ].freeze

  # Config files to scan. Each maps to its editor route; a /media/ value's
  # top-level YAML key becomes the ?focus target so the editor can activate
  # that input. file is resolved lazily so a missing file just yields nothing.
  CONFIG_SOURCES = [
    { file: -> { SiteConfig::SITE_FILE },        path_helper: :admin_edit_site_config_path,        label: "Site config" },
    { file: -> { SiteConfig::CUSTOM_CODE_FILE }, path_helper: :admin_edit_custom_code_config_path, label: "Custom code" },
    { file: -> { SiteConfig::FEATURES_PATH.join("podcast.yml").to_s }, path_helper: :admin_edit_podcast_config_path, label: "Podcast config" }
  ].freeze

  class << self
    # Cached (above threshold) or freshly-built index.
    def fetch
      if Medium.originals_only.count > CACHE_THRESHOLD
        Rails.cache.fetch(CACHE_KEY) { new.build }
      else
        new.build
      end
    end

    def invalidate!
      Rails.cache.delete(CACHE_KEY)
    end

    def config_backlinks_enabled?
      CONFIG_BACKLINKS_ENABLED
    end

    def global_tab_enabled?
      GLOBAL_TAB_ENABLED
    end
  end

  # => { "/media/..." => [ { kind:, label:, url:, global: Boolean } ] }
  def build
    index = Hash.new { |h, k| h[k] = [] }

    scan_content_sources(index)
    scan_config_sources(index) if self.class.config_backlinks_enabled?

    # Freeze into a plain hash so callers get [] for misses without mutating.
    index.default = [].freeze
    index
  end

  private

  def scan_content_sources(index)
    CONTENT_SOURCES.each do |source|
      model = source[:model].constantize
      model.find_each do |record|
        paths = paths_in(record.content) | paths_in_metadata(record.metadata)
        next if paths.empty?

        url = resolve_url(source[:path_helper], record)
        label = record_label(record)
        # Marked in the browser with a $ so it's visible which references are
        # what protects a file — and, on a file that's readable when you
        # expected it not to be, which reference is the public one.
        # Documentation has no audience and never responds to this.
        paid = record.respond_to?(:media_audience) && record.media_audience == "paid"
        paths.each do |path|
          index[path] << { kind: source[:kind], type: KIND_LABELS[source[:kind]], label: label, url: with_highlight(url, path), global: false, paid: paid }
        end
      end
    end
  end

  def scan_config_sources(index)
    CONFIG_SOURCES.each do |source|
      file = source[:file].call
      next unless File.exist?(file)

      data = YAML.safe_load(File.read(file)) rescue nil
      next unless data.is_a?(Hash)

      each_media_value(data) do |field_key, path|
        base = resolve_url(source[:path_helper])
        label = field_key ? "#{source[:label]} → #{field_key}" : source[:label]
        index[path] << { kind: "config", type: KIND_LABELS["config"], label: label, url: with_focus(base, field_key), global: true, paid: false }
      end
    end
  end

  # Media paths in free-text content (a post/page body). Paths appear inside
  # markdown links/images or HTML src/href, which delimit them — so filenames
  # with spaces or parens are captured whole. A bare-path fallback catches
  # unquoted occurrences (those can't contain spaces).
  def paths_in(text)
    return [] if text.blank?

    text = text.to_s
    paths = []
    paths.concat text.scan(/\]\((\/media\/[^)]+)\)/).flatten                        # ](/media/...)
    paths.concat text.scan(/(?:src|href)\s*=\s*["'](\/media\/[^"']+)["']/i).flatten # src/href="..."
    paths.concat text.scan(MEDIA_PATH)                                              # bare, unquoted
    paths.uniq
  end

  # Walk metadata (nested hashes/arrays) collecting /media/ paths from string
  # values, regardless of field name.
  def paths_in_metadata(value)
    found = []
    walk_strings(value) { |s| found.concat(value_paths(s)) }
    found.uniq
  end

  # Yield [field_key, media_path] for every /media/ value in the config,
  # where field_key is the *leaf* key whose value holds the path — e.g.
  # "artwork" for podcast.<slug>.artwork, "logo" for site.logo. That's the
  # field the editor should focus and the clearest thing to name in the
  # backlink label (the old top-level key sent podcast artwork to the slug,
  # which the editor focus then resolved to the wrong field).
  def each_media_value(node, key = nil, &block)
    case node
    when String
      value_paths(node).each { |path| yield key, path } if key
    when Hash
      node.each { |k, v| each_media_value(v, k.to_s, &block) }
    when Array
      node.each { |v| each_media_value(v, key, &block) }
    end
  end

  # Media paths from a single field value (metadata or config leaf). A bare
  # field value IS the path, so take the whole thing — this is what makes
  # filenames with spaces/parens (e.g. "/media/video/My Clip (2024).mp4")
  # match. Only fall back to text extraction when the value clearly embeds
  # markup rather than being a lone path.
  def value_paths(string)
    stripped = string.to_s.strip
    return [ stripped ] if stripped.start_with?("/media/") && !stripped.match?(/\]\(|=\s*["']|\n/)

    paths_in(string)
  end

  def walk_strings(value, &block)
    case value
    when String then yield value
    when Hash   then value.each_value { |v| walk_strings(v, &block) }
    when Array  then value.each { |v| walk_strings(v, &block) }
    end
  end

  def record_label(record)
    title = record.try(:title).presence
    title || File.basename(record.file_path.to_s)
  end

  def with_highlight(url, path)
    append_query(url, "highlight", path)
  end

  def with_focus(url, key)
    return url if key.blank?

    append_query(url, "focus", key)
  end

  def append_query(url, param, value)
    return url if url.blank?

    sep = url.include?("?") ? "&" : "?"
    "#{url}#{sep}#{param}=#{CGI.escape(value)}"
  end

  # Resolve an edit-path helper, tolerating routes not being available yet.
  # The index is also built during the boot-time ContentSync that drives
  # variant pruning — before the routes are drawn — where the url helpers
  # raise NoMethodError. The media→usage mapping (which prune_all! needs)
  # doesn't depend on URLs; those are only for the admin backlink UI, which
  # rebuilds the index once routes exist. So degrade to a nil link rather
  # than letting the whole index (and the prune) blow up.
  def resolve_url(helper, *args)
    public_send(helper, *args)
  rescue NoMethodError, NameError => e
    Rails.logger.debug { "[MediaUsageIndex] url helper #{helper} unavailable: #{e.message}" }
    nil
  end
end
