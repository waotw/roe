class Medium < ApplicationRecord
  has_many :media_references, dependent: :destroy
  has_many :posts, through: :media_references
  belongs_to :import, optional: true

  before_save :normalize_media_type
  after_create :queue_variant_generation, if: :image?

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

  def image?
    media_type == "images"
  end

  def variants_ready?
    return false unless image?

    # Check filesystem instead of DB
    source_path = Rails.root.join("site", file_path.sub(%r{^/}, "")).to_s
    ImageVariantGenerator.variants_exist?(source_path)
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
    return unless ImageVariantGenerator.available?

    GenerateImageVariantsJob.perform_later(file_path, nil)  # Pass nil for medium_id
  end

  def self.remove_by_file_path(file_path)
    medium = find_by(file_path: file_path)
    medium&.destroy
  end

  private

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
