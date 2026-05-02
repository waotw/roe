# frozen_string_literal: true

# Helpers for direct variant lookup. For full responsive `<picture>` output
# (srcset + WebP source + medium fallback img), use ResponsiveImageRenderer
# instead — that's the single source of truth for the policy that "the
# original is never served, only variants are."
module ImageVariantHelper
  # Web path to a single variant of an image. Falls back to the source path
  # when the variant doesn't exist on disk yet (e.g. variants haven't been
  # generated). Use this for admin grids and small UI affordances where a
  # full `<picture>` tag is overkill.
  #
  # Usage: image_variant_path(post.metadata['image'], :small)
  def image_variant_path(source_path, variant_name)
    return source_path if source_path.blank?
    return source_path unless ImageVariantGenerator.available?

    unless ImageVariantGenerator::VARIANTS.key?(variant_name.to_sym)
      Rails.logger.warn "[ImageVariants] Invalid variant name: #{variant_name}"
      return source_path
    end

    filesystem_path = ImageVariantGenerator.variant_path_for(source_path.to_s, variant_name)

    if File.exist?(filesystem_path)
      filesystem_path.sub(RoeSitePaths::SITE_PATH.to_s, "")
    else
      source_path
    end
  end

  # Convenience for admin views that want to know whether a Medium has
  # all variants generated yet. Reads `variants_status` for O(1) lookup
  # when the column is in agreement; falls back to the filesystem check
  # via Medium#variants_ready? for self-healing.
  def variants_ready?(medium)
    return false unless medium.is_a?(Medium)
    medium.variants_ready?
  end
end
