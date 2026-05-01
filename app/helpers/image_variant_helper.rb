# frozen_string_literal: true

module ImageVariantHelper
  # Returns the path to an image variant
  # Usage: image_variant_path(@post.featured_image, :medium)
  # Returns the path to an image variant
  # Usage: image_variant_path(@post.featured_image, :medium)
  def image_variant_path(source_path, variant_name)
    return source_path if source_path.blank?
    return source_path unless ImageVariantGenerator.available?

    # Validate variant name
    unless ImageVariantGenerator::VARIANTS.key?(variant_name.to_sym)
      Rails.logger.warn "[ImageVariants] Invalid variant name: #{variant_name}"
      return source_path
    end

    # Get filesystem path
    filesystem_path = ImageVariantGenerator.variant_path_for(source_path.to_s, variant_name)

    # Check if it exists
    if File.exist?(filesystem_path)
      # Convert to web path for image_tag
      filesystem_path.sub(RoeSitePaths::SITE_PATH.to_s, "")
    else
      source_path
    end
  end

  # Returns a picture tag with WebP + JPEG fallback
  # Usage: responsive_image_tag(@post.featured_image, alt: "Photo")
  def responsive_image_tag(source_path, **options)
    return image_tag(source_path, **options) unless ImageVariantGenerator.available?
    return image_tag(source_path, **options) unless image_file?(source_path)

    alt_text = options.delete(:alt) || ""
    css_class = options.delete(:class) || ""

    # Build WebP srcset
    webp_srcset = build_srcset(source_path, :webp)

    # Build fallback JPEG/PNG srcset
    fallback_srcset = build_srcset(source_path, :original)

    # Generate picture tag
    content_tag(:picture) do
      concat tag(:source, srcset: webp_srcset, type: "image/webp", sizes: "100vw")
      concat tag(:source, srcset: fallback_srcset, sizes: "100vw")
      concat image_tag(source_path, alt: alt_text, class: css_class, loading: "lazy", **options)
    end
  end

  # Check if a medium has all variants ready
  def variants_ready?(medium)
    return false unless medium.is_a?(Medium)
    return false unless medium.image?

    source_path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, "")).to_s
    ImageVariantGenerator.variants_exist?(source_path)
  end

  private

  def build_srcset(source_path, format)
    variants = %i[small medium large]
    srcset = variants.filter_map do |variant|
      if format == :webp
        path = webp_variant_path(source_path, variant)
      else
        path = image_variant_path(source_path, variant)
      end

      width = variant_width(variant)
      "#{path} #{width}w" if path != source_path
    end

    # Add original as largest
    srcset << "#{source_path} 2000w"
    srcset.join(", ")
  end

  def webp_variant_path(source_path, variant_name)
    variant_path = ImageVariantGenerator.variant_path_for(source_path, variant_name)
    webp_path = variant_path.sub(File.extname(variant_path), ".webp")

    # Fall back to JPEG if WebP doesn't exist
    File.exist?(File.join(RoeSitePaths::SITE_PATH, webp_path.sub(%r{^/}, ""))) ? webp_path : variant_path
  end

  def image_file?(path)
    %w[.jpg .jpeg .png .gif .webp].include?(File.extname(path.to_s).downcase)
  end

  def variant_width(variant)
    case variant
    when :thumb then 150
    when :small then 400
    when :medium then 800
    when :large then 1200
    else 2000
    end
  end
end
