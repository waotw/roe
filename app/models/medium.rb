class Medium < ApplicationRecord
  has_many :media_references, dependent: :destroy
  has_many :posts, through: :media_references
  belongs_to :import, optional: true

  before_save :normalize_media_type
  before_destroy :delete_variants, if: :image?
  after_create :queue_variant_generation, if: -> { image? && !Rails.env.production? }

  # Scope helpers for filtering
  scope :images, -> { where(media_type: "images") }
  scope :audio, -> { where(media_type: "audio") }
  scope :video, -> { where(media_type: "video") }
  scope :fonts, -> { where(media_type: "fonts") }
  scope :unused, -> {
      left_joins(:media_references)
        .where(media_references: { id: nil })
    }
  # Add this scope
  scope :originals_only, -> { where.not("file_path LIKE ?", "%/variants/%") }

  # Variant status scopes — back the indexed `variants_status` column.
  # Stamped by ImageVariantGenerator.mark_complete_for after a successful
  # generation run; row stays at the "pending" default until then. The
  # pending scope treats NULL the same as "pending" since older rows
  # predate the column default.
  scope :with_complete_variants, -> { where(variants_status: "complete") }
  scope :with_pending_variants, -> { where("variants_status IS NULL OR variants_status != ?", "complete") }

  def image?
    media_type == "images"
  end

  def variants_ready?
    return false unless image?
    # Fast path: trust the column when it says complete. mark_complete_for
    # only stamps "complete" after a post-loop variants_exist? check, so
    # a true here is a real "all on-disk variants present" signal.
    return true if variants_status == "complete"

    # Slow path / self-heal: column might not have been backfilled yet
    # (rows that predate the wired-up status). Confirm against the
    # filesystem and stamp the column on the way out so subsequent calls
    # take the fast path.
    source_path = File.join(RoeSitePaths::SITE_PATH, file_path.sub(%r{^/}, "")).to_s
    return false unless ImageVariantGenerator.variants_exist?(source_path)

    update_columns(variants_status: "complete", variants_generated_at: Time.current) if persisted?
    true
  end


  def variant_path(variant_name)
    return nil unless image?
    ImageVariantGenerator.variant_path_for(file_path, variant_name)
  end

  def variant_stats
    ImageVariantGenerator.stats_for(self)
  end

  def queue_variant_generation
    return unless image?

    ImageVariantGenerator.queue!(file_path)
  end

  def self.remove_by_file_path(file_path)
    medium = find_by(file_path: file_path)
    medium&.destroy
  end

  private

  def delete_variants
    return unless image?

    source_path = File.join(RoeSitePaths::SITE_PATH, file_path.sub(%r{^/}, ""))
    variants_dir = File.join(File.dirname(source_path), "variants")

    return unless Dir.exist?(variants_dir)

    # Delegate variant-path construction to ImageVariantGenerator so
    # naming stays in one place — this matters for HEIC/HEIF sources
    # where variants are emitted as .jpg, not .heic.
    ImageVariantGenerator::VARIANTS.keys.each do |variant_name|
      variant_file = ImageVariantGenerator.variant_path_for(source_path, variant_name)

      if File.exist?(variant_file)
        File.delete(variant_file)
        Rails.logger.info "[Medium] Deleted variant: #{variant_file}"
      end

      # Also check for .webp variant if it exists
      webp_file = variant_file.sub(File.extname(variant_file), ".webp")
      if File.exist?(webp_file)
        File.delete(webp_file)
        Rails.logger.info "[Medium] Deleted webp variant: #{webp_file}"
      end
    end
  rescue => e
    Rails.logger.error "[Medium] Failed to delete variants: #{e.message}"
  end

  def normalize_media_type
    # If media_type is blank, extract from file_path
    if media_type.blank? && file_path.present?
      self.media_type = File.extname(file_path).delete_prefix(".").downcase
    end

    extension = media_type&.downcase

    case extension
    when "png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "heic", "heif"
      self.media_type = "images"
    when "woff", "woff2", "ttf", "otf"
      self.media_type = "fonts"
    when "mp3", "m4a", "wav", "ogg", "flac", "aac"
      self.media_type = "audio"
    when "mp4", "webm", "ogv", "mov", "avi", "mkv"
      self.media_type = "video"
    end
  end
end
