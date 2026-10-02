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

  # Variant to drop into each cell by the gallery's column count. Each is ~2x
  # its display width in a 600px email body (1-col≈600, 2-col≈300, 3/4-col≈
  # 200/150), so the image stays sharp on retina without a bespoke crop:
  #   1 col  -> large  (1200px)   2x of 600
  #   2 cols -> medium (800px)    ~2.7x of 300
  #   3+ cols-> small  (400px)    2x+ of <=200
  GRID_VARIANT_BY_COLS = { 1 => :large, 2 => :medium }.freeze
  GRID_VARIANT_DEFAULT = :small

  # Standalone (non-gallery) body images: full body width, 2x retina.
  STANDALONE_VARIANT = :large

  # Email body width the display sizes are computed against.
  EMAIL_BODY_WIDTH = 600

  # Don't build absurdly narrow cells even if a future theme raises the
  # gallery column cap — below this the images are illegible on a phone.
  MAX_GRID_COLS = 6

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
    transform_galleries(doc)
    transform_standalone_pictures(doc)
    doc.to_html
  end

  private

  # Each `div.gallery` becomes either a stacked set of column tables (grid) or
  # a single linked image (carousel/slideshow). Replacing the whole `.gallery`
  # also drops its popover lightbox overlays, which live inside it.
  def transform_galleries(doc)
    doc.css("div.gallery").each do |gallery|
      replacement =
        if carousel?(gallery)
          build_carousel(gallery)
        else
          build_grid(gallery)
        end
      gallery.replace(replacement) if replacement
    end
  end

  def carousel?(gallery)
    gallery["class"].to_s.split.include?("gallery-carousel") ||
      gallery.key?("data-gallery-carousel")
  end

  # Carousel: show only the first image (the author chose "don't show all at
  # once"), linked to the post, at full body width. No "+N more" by decision.
  def build_carousel(gallery)
    img = gallery.at_css("img")
    return "" unless img

    src = first_present(img["src"])
    return "" if src.blank?

    tag = email_img(src, alt: img["alt"], prefer: [ STANDALONE_VARIANT ],
                    display_width: EMAIL_BODY_WIDTH, style: standalone_style)
    link_to_post(tag)
  end

  # Grid: one borderless table per gallery-row, stacked. Column count is read
  # from the gallery-col-N class, so raising the theme's column cap needs no
  # change here. Cells carry an "eg-cell" class the template's media query can
  # stack on narrow screens (clients that ignore it keep N-up — acceptable).
  def build_grid(gallery)
    rows = gallery.css("div.gallery-row")
    rows = [ gallery ] if rows.empty? # defensive: a gallery with loose items
    tables = rows.map { |row| build_grid_row(row) }.compact
    tables.join("\n")
  end

  def build_grid_row(row)
    items = row.css("div.gallery-item, figure.gallery-item")
    items = row.css("img").map { |i| i } if items.empty?
    imgs = items.map { |it| it.name == "img" ? it : it.at_css("img") }.compact
    return nil if imgs.empty?

    cols = column_count(row, imgs.length)
    variant = GRID_VARIANT_BY_COLS.fetch(cols, GRID_VARIANT_DEFAULT)
    cell_pct = (100.0 / cols).round(2)
    display_w = (EMAIL_BODY_WIDTH / cols)

    cells = imgs.map do |img|
      src = first_present(img["src"])
      next "" if src.blank?

      tag = email_img(src, alt: img["alt"], prefer: [ variant ],
                      display_width: display_w, style: grid_img_style)
      tag = link_to_post(tag)
      %(<td class="eg-cell" valign="top" width="#{cell_pct}%" style="padding:4px;">#{tag}</td>)
    end.join

    %(<table role="presentation" width="100%" cellpadding="0" cellspacing="0" ) +
      %(style="border-collapse:collapse;margin:0 0 8px;"><tr>#{cells}</tr></table>)
  end

  def column_count(row, fallback)
    klass = row["class"].to_s
    n = klass[/gallery-col-(\d+)/, 1]&.to_i
    n = fallback if n.nil? || n <= 0
    n.clamp(1, MAX_GRID_COLS)
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

  def grid_img_style
    "display:block;width:100%;max-width:100%;height:auto;border:0;"
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