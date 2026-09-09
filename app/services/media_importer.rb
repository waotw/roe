require "yaml"

# Pulls external http(s) media referenced across Roe content into the local
# media library. The Scanner finds references, the Fetcher downloads them, and
# MediaImportJob rewrites the references — the counterpart to the Files
# importer's bundle-aware copy, but for links instead of ZIP files.
module MediaImporter
  module_function

  # One external media reference found in content.
  #   url:      the external URL
  #   type:     :images | :audio | :video (also the media bucket name)
  #   record:   the Post/Page/Product it appears in
  #   location: frontmatter field name (String) or :body
  Ref = Struct.new(:url, :type, :record, :location, keyword_init: true)

  IMAGE_EXTS = %w[.jpg .jpeg .png .gif .webp .svg .avif .bmp .ico .tiff].freeze
  AUDIO_EXTS = %w[.mp3 .m4a .m4b .aac .wav .ogg .oga .opus .flac].freeze
  VIDEO_EXTS = %w[.mp4 .mov .webm .m4v .avi .mkv].freeze

  # Frontmatter fields whose value is media even when the URL has no telling
  # extension (e.g. an audio CDN link like …/play?id=123).
  IMAGE_FIELDS = %w[image artwork cover thumbnail banner og_image social_image logo icon].freeze
  AUDIO_FIELDS = %w[audio].freeze
  VIDEO_FIELDS = %w[video].freeze

  EXTERNAL = %r{\Ahttps?://}i

  def external?(url)
    url.is_a?(String) && url.match?(EXTERNAL)
  end

  # The media bucket a URL belongs to, or nil if it isn't media. A known media
  # frontmatter field wins over the extension; body refs pass field: nil and
  # fall back to the extension.
  def media_type(url, field: nil)
    f = field.to_s.downcase
    return :images if IMAGE_FIELDS.include?(f)
    return :audio  if AUDIO_FIELDS.include?(f)
    return :video  if VIDEO_FIELDS.include?(f)

    ext = File.extname(url.to_s.split(/[?#]/).first.to_s).downcase
    return :images if IMAGE_EXTS.include?(ext)
    return :audio  if AUDIO_EXTS.include?(ext)
    return :video  if VIDEO_EXTS.include?(ext)
    nil
  end

  # Posts/pages store an absolute file_path; products store a relative one.
  def content_path(record)
    path = record.file_path.to_s
    return nil if path.empty?
    path.start_with?("/") ? path : File.join(RoeSitePaths::SITE_PATH, path)
  end

  def split_frontmatter(content)
    if content =~ /\A\s*---\s*\n(.*?)\n---\s*\n?(.*)\z/m
      fm = (YAML.safe_load($1, permitted_classes: [ Date, Time, Symbol ]) rescue nil)
      [ fm.is_a?(Hash) ? fm : {}, $2 ]
    else
      [ {}, content.to_s ]
    end
  end

  # Image references in a markdown body — ![alt](url) and <img src>. Always
  # images regardless of extension (it's image markup).
  def image_urls(body)
    (body.to_s.scan(/!\[[^\]]*\]\(\s*<?([^)>\s]+)>?[^)]*\)/).flatten +
     body.to_s.scan(/<img\b[^>]*?\ssrc=["']([^"']+)["']/i).flatten)
  end

  # Non-image media references — plain [text](url) links and <audio>/<video>/
  # <source> tags. Classified by extension.
  def link_urls(body)
    (body.to_s.scan(/(?<!!)\[[^\]]*\]\(\s*<?([^)>\s]+)>?[^)]*\)/).flatten +
     body.to_s.scan(/<(?:audio|video|source)\b[^>]*?\ssrc=["']([^"']+)["']/i).flatten)
  end

  # Replace every downloaded URL with its local path in a record's file (both
  # frontmatter and body), then re-sync. url_map: { external_url => "/media/…" }.
  # Longest URLs first so one URL that's a prefix of another can't corrupt it.
  # Returns true when the file changed.
  def rewrite_file(record, url_map)
    path = content_path(record)
    return false unless path && File.exist?(path)

    original = File.read(path)
    updated = original.dup
    url_map.keys.sort_by { |u| -u.length }.each do |url|
      updated = updated.gsub(url, url_map[url]) if updated.include?(url)
    end
    return false if updated == original

    File.write(path, updated)
    # Config targets (podcast.yml) re-sync themselves; content files go through
    # ContentSync.
    record.respond_to?(:resync) ? record.resync : ContentSync.sync_file(path)
    true
  end
end
