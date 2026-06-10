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
    return simple_img_tag unless ImageVariantGenerator.available?
    return simple_img_tag unless image_file?

    # Check if variants exist
    source_full_path = File.join(RoeSitePaths::SITE_PATH, source_path.sub(%r{^/}, "")).to_s

    html = if ImageVariantGenerator.variants_exist?(source_full_path)
      build_picture_tag
    else
      # Queue generation for first view, show original for now. queue! is
      # idempotent — Rails.cache flag dedups subsequent renders of this
      # path until the job clears it (or the TTL expires).
      ImageVariantGenerator.queue!(source_path)
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
    fallback_src = variant_web_path(DEFAULT_IMG_VARIANT) || source_path
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
    variants = VARIANT_WIDTHS.map do |variant_name, width|
      webp_path = webp_variant_path(variant_name)
      next unless webp_path && variant_exists?(webp_path)

      "#{ERB::Util.html_escape(webp_path)} #{width}w"
    end.compact

    variants.any? ? variants.join(", ") : nil
  end

  def build_fallback_srcset
    variants = VARIANT_WIDTHS.map do |variant_name, width|
      web_path = variant_web_path(variant_name)
      next unless web_path && variant_exists?(web_path)

      "#{ERB::Util.html_escape(web_path)} #{width}w"
    end.compact

    variants.any? ? variants.join(", ") : nil
  end

  # Web path for a native-format variant of the source.
  # Returns nil when the variant generator can't produce one (no source).
  def variant_web_path(variant_name)
    filesystem_path = ImageVariantGenerator.variant_path_for(source_path, variant_name)
    filesystem_path.sub(RoeSitePaths::SITE_PATH.to_s, "")
  end

  def webp_variant_path(variant_name)
    return nil unless ImageVariantGenerator::GENERATE_WEBP

    web_path = variant_web_path(variant_name)
    web_path.sub(File.extname(web_path), ".webp")
  end

  def variant_exists?(path)
    # Delegate path resolution to ImageVariantGenerator.normalize_path so
    # this stays correct under the versioned `current/` layout — site
    # files live under RoeSitePaths::SITE_PATH (/roe/site), not under
    # Rails.root (/roe/current). The previous start_with?(Rails.root)
    # check missed every filesystem path coming back from
    # `variant_path_for`, so build_fallback_srcset treated all variants
    # as missing and the picture tag silently degraded to the original.
    File.exist?(ImageVariantGenerator.normalize_path(path))
  end

  def image_file?
    ImageVariantGenerator::IMAGE_EXTENSIONS.include?(File.extname(source_path).downcase)
  end
end
