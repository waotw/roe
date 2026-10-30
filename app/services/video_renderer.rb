# frozen_string_literal: true

# VideoRenderer — the one place a <video> tag is built for site content, so
# the markdown embed, the player card and the video post template all serve
# the same thing:
#
#   - the web versions VideoVariantGenerator made (720p first, 1080p as the
#     second source) instead of the original, when they exist
#   - a poster frame, the video's real width and height (so the page
#     doesn't jump when it loads), preload="metadata" and playsinline
#
# Content files are never rewritten: a post still says /media/video/x.mov,
# and the renditions are swapped in here when the page is rendered. When
# there are no renditions (no ffmpeg on the computer that added the video,
# or still encoding), the original is served, as before.
#
# Reads only the manifest and checks files exist — it never runs ffmpeg or
# ffprobe — so it works the same on a live site without either.
class VideoRenderer
  MIME_TYPES = {
    ".mp4" => "video/mp4", ".m4v" => "video/mp4", ".mov" => "video/quicktime",
    ".webm" => "video/webm", ".ogv" => "video/ogg", ".mkv" => "video/x-matroska"
  }.freeze

  # Facts about what to serve for one video `src` (a web path, or an
  # external URL, which is passed through untouched).
  Plan = Struct.new(:sources, :poster, :width, :height, keyword_init: true)

  def self.plan(src)
    new(src).plan
  end

  # A <video> element. `attrs` are extra HTML attributes (class, controls,
  # data-*); `inner` is HTML placed after the <source> tags (fallback text).
  #
  # width/height let the browser reserve the right space before the video
  # loads. They come with `height:auto; max-width:100%` so they only set
  # the shape, never a fixed size: a theme rule like `.video-player-video
  # { width: 100%; aspect-ratio: 16/9 }` still wins, and a bare embed
  # shrinks to fit the column instead of overflowing it.
  def self.tag(src, attrs: {}, inner: "")
    p = plan(src)
    sized = p.width.to_i.positive? && p.height.to_i.positive?
    html_attrs = {
      "preload" => "metadata",
      "playsinline" => true,
      "poster" => p.poster,
      "width" => (p.width if sized),
      "height" => (p.height if sized),
      "style" => ("max-width:100%;height:auto" if sized)
    }.merge(attrs.transform_keys(&:to_s))

    rendered_attrs = html_attrs.filter_map do |name, value|
      next if value.nil? || value == false
      value == true ? name : %(#{name}="#{ERB::Util.html_escape(value)}")
    end

    sources = p.sources.map do |s|
      type = s[:type] ? %( type="#{s[:type]}") : ""
      %(<source src="#{ERB::Util.html_escape(s[:src])}"#{type}>)
    end

    %(<video #{rendered_attrs.join(' ')}>#{sources.join}#{inner}</video>).html_safe
  end

  def initialize(src)
    @src = src.to_s.strip
  end

  def plan
    return Plan.new(sources: [], poster: nil) if @src.empty?
    return original_only unless local?

    source = VideoVariantGenerator.normalize_path(path_only)
    renditions = VideoVariantGenerator.available_renditions(source)
    return original_only if renditions.empty?

    manifest = VideoVariantGenerator.current_manifest(source)
    first = renditions.first
    poster = manifest["poster"] if manifest["poster"] && File.file?(VideoVariantGenerator.variant_path_for(source, VideoVariantGenerator::POSTER))

    Plan.new(
      sources: renditions.map { |r| { src: r["path"], type: "video/mp4" } },
      poster: poster,
      width: first["width"],
      height: first["height"]
    )
  end

  private

  # Only Roe's own media folder has renditions; anything else (a YouTube
  # file URL, another site's MP4) is served as written.
  def local? = path_only.start_with?("/media/")

  # Without a query string or fragment (#t=10 to start at 10 seconds), and
  # with %-escapes decoded: Markdown links arrive URL-encoded ("CLOSER_%20a
  # dance…"), and the file on disk has real spaces.
  def path_only
    raw = @src.split(/[?#]/).first.to_s
    raw.include?("%") ? CGI.unescape(raw.tr("+", "\u0000")).tr("\u0000", "+") : raw
  end

  def original_only
    type = MIME_TYPES[File.extname(path_only).downcase]
    Plan.new(sources: [ { src: @src, type: type } ], poster: nil, width: nil, height: nil)
  end
end
