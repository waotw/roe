# frozen_string_literal: true

class ResponsiveImageRenderer
  # Widths used to build srcset descriptors. `thumb` is intentionally
  # excluded — it's a square crop, not a width-scaled variant. Order
  # matters: smallest first so the browser walks ascending widths.
  VARIANT_WIDTHS = {
    small:  400,
    medium: 800,
    large:  1200,
    xl:     1800
  }.freeze

  # The variant whose web path becomes the `<img>` `src` inside the
  # picture tag. Browsers fall back to `src` only when none of the
  # `<source>` srcsets match, which on modern browsers means basically
  # never — but it's also what JS reads via `img.src`, what scrapers
  # see, and what gets used when CSS does `background-image` etc. So
  # it has to point at a real served-friendly variant, not the original.
  DEFAULT_IMG_VARIANT = :medium

  attr_reader :source_path, :options

  def initialize(source_path, **options)
    @source_path = source_path
    @options = options
  end

  def self.render(source_path, **options)
    new(source_path, **options).render
  end

  def render
    return "" if source_path.blank?
    return simple_img_tag unless image_file?

    source_full_path = File.join(RoeSitePaths::SITE_PATH, source_path.sub(%r{^/}, "")).to_s

    # Serve a <picture> whenever a full variant set exists on disk — no
    # matter how it got there: generated here by libvips, generated on
    # another machine and synced/deployed, or placed by hand. libvips is
    # only needed to *create* variants, never to *serve* them, so we check
    # for the files first and gate generation (not serving) on it.
    html = if ImageVariantGenerator.variants_exist?(source_full_path)
      build_picture_tag
    elsif ImageVariantGenerator.available?
      # Missing but we can build them: queue and show the original until
      # ready. queue! is idempotent (Rails.cache flag dedups re-renders
      # until the job clears it).
      ImageVariantGenerator.queue!(source_path)
      simple_img_tag
    else
      # No variants and no libvips to make them → serve the original.
      simple_img_tag
    end

    html.html_safe
  end

  private

  def build_picture_tag
    alt_text = ERB::Util.html_escape(options[:alt] || "")
    css_class = ERB::Util.html_escape(options[:class] || "")
    loading = ERB::Util.html_escape(options[:loading] || "lazy")
    sizes = ERB::Util.html_escape(options[:sizes] || "(min-width: 1200px) 1200px, 100vw")

    # Build additional attributes
    extra_attrs = build_extra_attributes

    # Use String concatenation with + instead of << to avoid frozen string issues
    html = +"<picture>"

    # WebP source (if available and enabled)
    if ImageVariantGenerator::GENERATE_WEBP
      webp_srcset = build_webp_srcset
      if webp_srcset.present?
        html << "<source srcset=\"#{webp_srcset}\" type=\"image/webp\" sizes=\"#{sizes}\">"
      end
    end

    # Fallback JPEG/PNG source
    fallback_srcset = build_fallback_srcset
    if fallback_srcset.present?
      html << "<source srcset=\"#{fallback_srcset}\" sizes=\"#{sizes}\">"
    end

    # Fallback img tag — points at the medium variant rather than the
    # source. Reaching this `<img>` means no `<source>` srcset matched
    # (rare on modern browsers), but it's also what JS, scrapers, and
    # CSS background-image consumers see. Per "never serve originals",
    # the original is an on-disk archive only; the picture tag's variant
    # menu is the entire serving menu.
    fallback_src = fallback_img_web_path || source_path
    html << "<img src=\"#{ERB::Util.html_escape(fallback_src)}\" "
    html << "alt=\"#{alt_text}\" "
    html << "class=\"#{css_class}\" " if css_class.present?
    html << "loading=\"#{loading}\" decoding=\"async\" "
    html << extra_attrs if extra_attrs.present?
    html << ">"

    html << "</picture>"
    html
  end

  def simple_img_tag
    alt_text = ERB::Util.html_escape(options[:alt] || "")
    css_class = ERB::Util.html_escape(options[:class] || "")
    loading = ERB::Util.html_escape(options[:loading] || "lazy")
    extra_attrs = build_extra_attributes

    # Use + to make string mutable
    html = +"<img src=\"#{ERB::Util.html_escape(source_path)}\" "
    html << "alt=\"#{alt_text}\" "
    html << "class=\"#{css_class}\" " if css_class.present?
    html << "loading=\"#{loading}\" "
    html << extra_attrs if extra_attrs.present?
    html << ">"
    html
  end

  def build_extra_attributes
    # Extract known options, everything else becomes an HTML attribute
    known_keys = [ :alt, :class, :loading, :sizes ]
    extra = options.except(*known_keys)

    extra.map { |k, v| "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join(" ")
  end

  # Both srcset builders intentionally OMIT the original. The originals-
  # never-served policy means the variant menu is the entire serving
  # menu; the original lives on disk as the source-of-truth archive
  # for re-derivation only. simple_img_tag remains the fail-safe for
  # the cases when variants aren't ready yet (queued first-render) or
  # libvips is unavailable — there, falling back to the original is
  # better than serving nothing.

  def build_webp_srcset
    srcset_for(:webp)
  end

  def build_fallback_srcset
    srcset_for(:native)
  end

  # {variant_name => actual pixel width} for the limit variants present on
  # disk (native measured first, webp as a fallback measurement), read once
  # per render via FastImage — no native image lib, so it works on the
  # libvips-less serving path. thumb is excluded (square crop, not a width).
  def measured_variant_widths
    @measured_variant_widths ||= ImageVariantGenerator::VARIANTS.keys.each_with_object({}) do |name, acc|
      next if name == :thumb
      native = ImageVariantGenerator.variant_path_for(source_path, name)
      webp   = native.sub(File.extname(native), ".webp")
      file   = File.exist?(native) ? native : (File.exist?(webp) ? webp : nil)
      next unless file
      width = ImageVariantGenerator.image_width(file)
      acc[name] = width if width
    end
  end

  # Build "url widthw" descriptors from existing variants — ascending and
  # DEDUPED by ACTUAL width. A source smaller than a variant's limit is
  # never upscaled, so several variants can share one pixel width; we
  # advertise that width once, with an honest descriptor.
  def srcset_for(kind)
    seen = {}
    measured_variant_widths.sort_by { |_name, width| width }.each do |name, width|
      next if seen.key?(width)
      native = ImageVariantGenerator.variant_path_for(source_path, name)
      fs = kind == :webp ? native.sub(File.extname(native), ".webp") : native
      next unless File.exist?(fs)
      seen[width] = web_path_for(fs)
    end
    return nil if seen.empty?

    seen.map { |width, web| "#{ERB::Util.html_escape(web)} #{width}w" }.join(", ")
  end

  # Web path for the <img> fallback inside <picture>: the variant nearest
  # the default (medium) target, else the largest available — the default
  # itself may not exist for a small source that skipped it.
  def fallback_img_web_path
    return nil if measured_variant_widths.empty?

    target = VARIANT_WIDTHS[DEFAULT_IMG_VARIANT]
    name   = measured_variant_widths.min_by { |_n, w| (w - target).abs }&.first
    return nil unless name

    native = ImageVariantGenerator.variant_path_for(source_path, name)
    File.exist?(native) ? web_path_for(native) : nil
  end

  def web_path_for(filesystem_path)
    filesystem_path.sub(RoeSitePaths::SITE_PATH.to_s, "")
  end

  def image_file?
    ImageVariantGenerator::IMAGE_EXTENSIONS.include?(File.extname(source_path).downcase)
  end
end
