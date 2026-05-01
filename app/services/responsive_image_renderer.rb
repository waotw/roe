# frozen_string_literal: true

class ResponsiveImageRenderer
  VARIANT_WIDTHS = {
    small: 400,
    medium: 800,
    large: 1200
  }.freeze

  attr_reader :source_path, :options

  def initialize(source_path, **options)
    @source_path = source_path
    @options = options
  end

  def self.render(source_path, **options)
    new(source_path, **options).render
  end

  def render
    return '' if source_path.blank?
    return simple_img_tag unless ImageVariantGenerator.available?
    return simple_img_tag unless image_file?

    # Check if variants exist
    source_full_path = File.join(RoeSitePaths::SITE_PATH, source_path.sub(%r{^/}, "")).to_s

    if ImageVariantGenerator.variants_exist?(source_full_path)
      build_picture_tag
    else
      # Queue generation for first view, show original for now
      queue_variant_generation(source_path) unless already_queued?(source_path)
      simple_img_tag
    end
  end

  private

  def queue_variant_generation(path)
    GenerateImageVariantsJob.perform_later(path, nil)
  rescue => e
    Rails.logger.warn "[ResponsiveImageRenderer] Could not queue: #{e.message}"
  end

  def already_queued?(path)
    # Check if a job for this path already exists in the queue
    # Arguments are stored as serialized JSON in SQLite
    SolidQueue::Job
      .where(class_name: 'GenerateImageVariantsJob')
      .where(finished_at: nil)
      .exists?(["arguments LIKE ?", "%#{path}%"])
  rescue
    false  # If check fails, allow queuing
  end

  def build_picture_tag
    alt_text = ERB::Util.html_escape(options[:alt] || '')
    css_class = ERB::Util.html_escape(options[:class] || '')
    loading = ERB::Util.html_escape(options[:loading] || 'lazy')
    sizes = ERB::Util.html_escape(options[:sizes] || '(min-width: 1200px) 1200px, 100vw')

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

    # Fallback img tag
    html << "<img src=\"#{ERB::Util.html_escape(source_path)}\" "
    html << "alt=\"#{alt_text}\" "
    html << "class=\"#{css_class}\" " if css_class.present?
    html << "loading=\"#{loading}\" decoding=\"async\" "
    html << extra_attrs if extra_attrs.present?
    html << ">"

    html << "</picture>"
    html
  end

  def simple_img_tag
    alt_text = ERB::Util.html_escape(options[:alt] || '')
    css_class = ERB::Util.html_escape(options[:class] || '')
    loading = ERB::Util.html_escape(options[:loading] || 'lazy')
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

    extra.map { |k, v| "#{k}=\"#{ERB::Util.html_escape(v)}\"" }.join(' ')
  end

  def build_webp_srcset
    variants = VARIANT_WIDTHS.map do |variant_name, width|
      webp_path = webp_variant_path(variant_name)
      next unless webp_path && variant_exists?(webp_path)

      "#{ERB::Util.html_escape(webp_path)} #{width}w"
    end.compact

    # Add original as largest if it exists as WebP
    original_webp = source_path.sub(File.extname(source_path), '.webp')
    if File.exist?(File.join(RoeSitePaths::SITE_PATH, original_webp.sub(%r{^/}, "")))
      variants << "#{ERB::Util.html_escape(original_webp)} 2000w"
    end

    variants.any? ? variants.join(', ') : nil
  end

  def build_fallback_srcset
    variants = VARIANT_WIDTHS.map do |variant_name, width|
      filesystem_path = ImageVariantGenerator.variant_path_for(source_path, variant_name)
      next unless variant_exists?(filesystem_path)

      # Convert filesystem path to web path for srcset
      web_path = filesystem_path.sub(RoeSitePaths::SITE_PATH.to_s, "")
      "#{ERB::Util.html_escape(web_path)} #{width}w"
    end.compact

    # Add original as largest
    variants << "#{ERB::Util.html_escape(source_path)} 2000w"

    variants.join(', ')
  end


  def webp_variant_path(variant_name)
    return nil unless ImageVariantGenerator::GENERATE_WEBP

    filesystem_path = ImageVariantGenerator.variant_path_for(source_path, variant_name)
    webp_filesystem = filesystem_path.sub(File.extname(filesystem_path), '.webp')

    # Convert to web path
    webp_filesystem.sub(RoeSitePaths::SITE_PATH.to_s, "")
  end

  def variant_exists?(path)
    # If it's already a filesystem path, use it directly
    if path.start_with?(Rails.root.to_s)
      File.exist?(path)
    else
      # Convert web path to filesystem path
      full_path = File.join(RoeSitePaths::SITE_PATH, path.to_s.sub(%r{^/}, ""))
      File.exist?(full_path)
    end
  end

  def image_file?
    ImageVariantGenerator::IMAGE_EXTENSIONS.include?(File.extname(source_path).downcase)
  end
end
