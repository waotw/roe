require "mini_magick"

# Reads pixel dimensions of an image file via mini_magick and caches the
# result so repeated lookups (every page render that emits OG/Twitter
# meta) don't fork an ImageMagick subprocess each time. Cache key
# includes the file mtime so an edited image invalidates automatically.
#
# Returns a {width:, height:} hash, or nil if the file can't be opened
# or is a format we'd rather skip in social meta (SVG, primarily —
# Twitter rejects vector image cards).
class ImageDimensions
  CACHE_TTL = 24.hours

  # Formats we *will* report dimensions for. Anything else (SVG, ICO,
  # PDF, etc.) returns nil so callers know to skip emitting og:image
  # for that file. Social-card crawlers expect raster image formats.
  SUPPORTED_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze

  class << self
    def for(path)
      return nil unless path.is_a?(String) && !path.empty?
      return nil unless supported_extension?(path)
      return nil unless File.file?(path)

      Rails.cache.fetch(cache_key(path), expires_in: CACHE_TTL) do
        read_dimensions(path)
      end
    end

    # Convenience that takes the same image references SeoHelper handles
    # (absolute filesystem paths, /media/foo.jpg style URLs, etc.) and
    # resolves them to a filesystem path before measuring.
    def for_url(url_or_path)
      return nil if url_or_path.blank?

      candidate = resolve_local_path(url_or_path.to_s)
      return nil unless candidate

      self.for(candidate)
    end

    def supported_extension?(path)
      SUPPORTED_EXTENSIONS.include?(File.extname(path).downcase)
    end

    private

    def cache_key(path)
      mtime = File.mtime(path).to_i rescue 0
      [ "image_dimensions", path, mtime ].join(":")
    end

    def read_dimensions(path)
      image = MiniMagick::Image.open(path)
      { width: image.width, height: image.height }
    rescue StandardError => e
      Rails.logger.debug "[ImageDimensions] read failed for #{path}: #{e.class} #{e.message}"
      nil
    end

    # Map a URL-style reference (e.g. "/media/foo.jpg",
    # "/system/assets/images/foo.png", "https://example.com/foo.jpg") to
    # the on-disk file. Absolute http(s) URLs return nil — we don't
    # download remote images to measure them; the og:image:width tags
    # are best-effort and remote-hosted images can ship without them.
    def resolve_local_path(url_or_path)
      return nil if url_or_path =~ %r{\Ahttps?://}i

      # Already an absolute filesystem path
      return url_or_path if url_or_path.start_with?("/") && File.file?(url_or_path)

      site_root = RoeSitePaths::SITE_PATH
      clean     = url_or_path.sub(%r{\A/}, "")

      candidates = [
        File.join(site_root, clean),
        File.join(site_root, "media", clean.sub(%r{\Amedia/}, "")),
        File.join(site_root, "system", "assets", "images", clean.sub(%r{\Asystem/assets/images/}, ""))
      ]
      candidates.find { |c| File.file?(c) }
    end
  end
end
