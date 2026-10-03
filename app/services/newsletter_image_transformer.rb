# frozen_string_literal: true

# Rewrites a post's rendered content HTML into something email clients can
# actually display. The web renderer emits responsive `<picture>` tags with
# `srcset` and CSS-grid galleries with a JS/popover lightbox — all of which
# email clients (Gmail, Outlook, Yahoo, even Apple Mail) ignore or strip.
# This collapses that markup to the email-safe subset: a single `<img>` per
# image (never `<picture>`/`srcset`/webp), multi-column galleries rebuilt as
# `<table>`s, absolute URLs, and retina sizing (the file is ~2x the display
# width, with width/height attrs for Outlook and max-width:100%/height:auto
# for everything else).
#
# Why a 2x file + half-size display: it's the only retina technique email
# clients honour. srcset is silently dropped everywhere, so a width-scaled
# variant twice the cell's display size, shown at the display size, is the
# reliable way to stay sharp on high-DPI screens.
class NewsletterImageTransformer
  # The trailing "-<variant>.<ext>" that every generated variant web path
  # carries, e.g. ".../name-medium.jpg". Native formats only — email never
  # gets webp (Outlook can't render it), so we keep whatever native ext the
  # web renderer already chose for the <img> fallback.
  VARIANT_RE = /-(thumb|small|medium|large|xl)(\.(?:jpe?g|png|gif))$/i

  # Standalone (non-gallery) body images: full body width, 2x retina.
  STANDALONE_VARIANT = :large

  # Email body width the display sizes are computed against.
  EMAIL_BODY_WIDTH = 600

  def initialize(html, site_url:, post_url: nil)
    @html = html.to_s
    @site_url = site_url.to_s.sub(%r{/\z}, "")
    @post_url = post_url
  end

  def self.transform(html, site_url:, post_url: nil)
    new(html, site_url: site_url, post_url: post_url).transform
  end

  def transform
    return @html if @html.blank?

    doc = Nokogiri::HTML.fragment(@html)
    remove_galleries(doc)
    transform_standalone_pictures(doc)
    doc.to_html
  end

  private

  # Galleries are dropped from newsletters entirely. The web lays them out with
  # CSS grid and crops cells to squares with object-fit — neither of which email
  # supports, so a faithful render isn't possible yet. Rendering them with their
  # natural aspect ratios looked unpredictable (wide and portrait images jammed
  # together), so until the variant epic can composite a gallery into one
  # flattened image (Substack-style), the whole `div.gallery` is removed —
  # images, captions, and lightbox markup with it. Standalone images are
  # untouched and still render.
  def remove_galleries(doc)
    doc.css("div.gallery").each(&:remove)
  end

  # Standalone images: collapse each <picture> (and its srcset) to one <img>
  # at the large variant, full body width. Runs after galleries so only
  # non-gallery pictures remain. The <picture> may sit inside a <figure> for
  # captions — replacing just the <picture> keeps the <figcaption>.
  def transform_standalone_pictures(doc)
    doc.css("picture").each do |picture|
      img = picture.at_css("img")
      if img.nil?
        picture.remove
        next
      end

      src = first_present(img["src"])
      if src.blank?
        picture.remove
        next
      end

      tag = email_img(src, alt: img["alt"], prefer: [ STANDALONE_VARIANT ],
                      display_width: EMAIL_BODY_WIDTH, style: standalone_style)
      picture.replace(tag)
    end

    # Any bare <img> the renderer emitted outside a <picture> (rare) — just
    # make its src absolute and give it email-safe sizing.
    doc.css("img").each do |img|
      next if img["data-email-done"] # already built by us (fragments re-query)
      src = first_present(img["src"])
      next if src.blank?
      img["src"] = absolute(src)
      merge_style(img, standalone_style)
    end
  end

  # Build an <img> string: picks the best available native variant at/above
  # the preferred one, makes the URL absolute, and sets retina width/height
  # (file ≈2x, display = half) plus the email-safe inline style.
  def email_img(current_src, alt:, prefer:, display_width:, style:)
    web = pick_variant(current_src, prefer)
    abs = absolute(web)
    w, h = display_dimensions(web, display_width)

    attrs = +%(<img src="#{escape(abs)}" alt="#{escape(alt.to_s)}")
    attrs << %( width="#{w}") if w
    attrs << %( height="#{h}") if h
    attrs << %( style="#{style}" data-email-done="1">)
    attrs
  end

  # Try the preferred variant, then walk down the ladder to the largest that
  # exists on disk (a small source may never have produced `large`). Falls
  # back to the original src when nothing matches (non-variant path, animated
  # GIF served as its original, etc).
  def pick_variant(current_src, prefer)
    m = current_src.match(VARIANT_RE)
    return current_src unless m

    ext = m[2]
    base = current_src[0...m.begin(0)]
    order = (prefer.map(&:to_s) + %w[large medium small xl thumb]).uniq
    order.each do |v|
      candidate = "#{base}-#{v}#{ext}"
      return candidate if File.exist?(fs_path(candidate))
    end
    current_src
  end

  # display width given, derive the matching height from the file's real
  # aspect ratio so Outlook (which honours width/height attrs) keeps the shape.
  # height:auto in the inline style overrides this for CSS-capable clients.
  def display_dimensions(web, display_width)
    dims = image_size(fs_path(web))
    return [ display_width, nil ] unless dims

    iw, ih = dims
    return [ display_width, nil ] if iw.to_i <= 0 || ih.to_i <= 0

    w = [ display_width, iw ].min # never upscale past the file's real width
    h = (w.to_f * ih / iw).round
    [ w, h ]
  end

  def image_size(path)
    return nil unless File.file?(path)
    require "fastimage"
    FastImage.size(path)
  rescue StandardError => e
    Rails.logger.debug { "[NewsletterImage] size read failed for #{path}: #{e.message}" }
    nil
  end

  def link_to_post(inner)
    return inner if @post_url.blank?
    %(<a href="#{escape(absolute(@post_url))}" style="text-decoration:none;">#{inner}</a>)
  end

  def standalone_style
    "display:block;max-width:100%;height:auto;margin:0 auto;"
  end

  def merge_style(node, style)
    existing = node["style"].to_s
    node["style"] = existing.present? ? "#{existing.sub(/;?\z/, ';')}#{style}" : style
  end

  def absolute(path)
    p = path.to_s
    return p if p.start_with?("http://", "https://")
    return "#{@site_url}#{p}" if p.start_with?("/")
    p
  end

  def fs_path(web)
    File.join(RoeSitePaths::SITE_PATH, web.to_s.sub(%r{^/}, "")).to_s
  end

  def first_present(*values)
    values.find { |v| v.to_s.strip.present? }
  end

  def escape(str)
    ERB::Util.html_escape(str.to_s)
  end
end