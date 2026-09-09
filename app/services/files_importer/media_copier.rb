require "digest"

# Bundle-aware media handling for the Files importer. Given a document's
# markdown body, it finds local asset references (relative or root-absolute
# links whose files live inside the import), copies each into
# /site/media/<bucket>, and rewrites the reference to the Roe media path.
# External http(s) links are left untouched — those belong to the Media
# Importer.
class FilesImporter::MediaCopier
  BUCKETS = {
    images: %w[.jpg .jpeg .png .gif .webp .svg .avif .bmp .ico .tiff],
    audio:  %w[.mp3 .m4a .m4b .aac .wav .ogg .oga .opus .flac],
    video:  %w[.mp4 .mov .webm .m4v .avi .mkv],
    files:  %w[.pdf .epub .zip .doc .docx .csv]
  }.freeze

  # Markdown image/link targets: ![alt](url "title") and [text](url "title").
  LINK_RE = /(!?)\[([^\]]*)\]\(\s*(<[^>]+>|[^)\s]+)((?:\s+"[^"]*")?)\s*\)/

  SKIP_SCHEMES = %r{\A(?:https?:|//|data:|mailto:|tel:|#|/media/)}i

  def initialize(root:, media_root: File.join(RoeSitePaths::SITE_PATH, "media"))
    @root           = File.expand_path(root)
    @media_root     = media_root
    @copied_sources = Set.new # absolute source paths already copied
  end

  # Returns [rewritten_body, [copied "/media/..." paths]]. source_path is the
  # doc's path within the import root, used to resolve relative asset refs.
  def rewrite(body, source_path)
    copied = []
    new_body = body.to_s.gsub(LINK_RE) do
      bang, text, raw_url, title = $1, $2, $3, $4
      url = raw_url.delete_prefix("<").delete_suffix(">")

      resolved = resolve(url, source_path)
      if resolved
        media_path = copy_asset(resolved)
        if media_path
          copied << media_path
          next "#{bang}[#{text}](#{media_path}#{title})"
        end
      end
      $& # unchanged
    end
    [ new_body, copied ]
  end

  # Rewrites local media references inside a frontmatter hash — a cover `image`,
  # an `audio`/`artwork` field, or any custom field whose value points at a
  # bundled file. Non-media values (titles, slugs, the source .md) resolve to
  # nothing and pass through untouched. Returns [rewritten_hash, [copied paths]].
  def rewrite_metadata(metadata, source_path)
    copied = []
    rewritten = metadata.transform_values { |value| rewrite_value(value, source_path, copied) }
    [ rewritten, copied ]
  end

  # For "import all media": copy every bundled media file not already pulled in
  # by a reference. Returns the copied "/media/..." paths.
  def copy_unreferenced
    copied = []
    Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).each do |abs|
      next unless File.file?(abs) && bucket_for(abs) && !@copied_sources.include?(File.expand_path(abs))
      path = copy_asset(File.expand_path(abs))
      copied << path if path
    end
    copied
  end

  private

  def rewrite_value(value, source_path, copied)
    case value
    when String
      resolved = resolve(value, source_path)
      media_path = resolved && copy_asset(resolved)
      if media_path
        copied << media_path
        media_path
      else
        value
      end
    when Array
      value.map { |v| rewrite_value(v, source_path, copied) }
    else
      value
    end
  end

  # Absolute path to a bundled asset the URL points at, or nil when it's
  # external, missing, or escapes the import root.
  def resolve(url, source_path)
    return nil if url.blank? || url.match?(SKIP_SCHEMES)

    clean = url.split(/[?#]/).first.to_s
    clean = CGI.unescape(clean)
    return nil if clean.blank?

    candidate =
      if clean.start_with?("/")
        File.join(@root, clean.sub(%r{\A/+}, ""))
      else
        File.expand_path(File.join(File.dirname(File.join(@root, source_path)), clean))
      end

    candidate = File.expand_path(candidate)
    return nil unless candidate.start_with?(@root + File::SEPARATOR)
    File.file?(candidate) ? candidate : nil
  end

  # Copies the asset into the right bucket, deduped by content, and returns its
  # "/media/<bucket>/<file>" path (nil for unknown extensions).
  def copy_asset(abs)
    bucket = bucket_for(abs)
    return nil unless bucket

    dir = File.join(@media_root, bucket.to_s)
    FileUtils.mkdir_p(dir)
    filename = destination_name(dir, abs)
    dest = File.join(dir, filename)
    FileUtils.cp(abs, dest) unless File.exist?(dest)
    @copied_sources << File.expand_path(abs)
    "/media/#{bucket}/#{filename}"
  end

  def bucket_for(abs)
    ext = File.extname(abs).downcase
    BUCKETS.find { |_, exts| exts.include?(ext) }&.first
  end

  # Preserve the source filename; on collision reuse it when byte-identical,
  # otherwise disambiguate with -2, -3, …
  def destination_name(dir, abs)
    base = sanitize(File.basename(abs))
    dest = File.join(dir, base)
    return base if !File.exist?(dest) || same_file?(dest, abs)

    ext  = File.extname(base)
    stem = File.basename(base, ext)
    n = 2
    loop do
      candidate = "#{stem}-#{n}#{ext}"
      path = File.join(dir, candidate)
      return candidate if !File.exist?(path) || same_file?(path, abs)
      n += 1
    end
  end

  def same_file?(a, b)
    File.size(a) == File.size(b) && Digest::SHA256.file(a) == Digest::SHA256.file(b)
  end

  def sanitize(name)
    name.gsub(/[^\w.\-]+/, "-").sub(/\A-+/, "").presence || "asset"
  end
end
