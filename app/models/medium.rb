class Medium < ApplicationRecord
  has_many :media_references, dependent: :destroy
  has_many :posts, through: :media_references

  before_save :normalize_media_type

  # Scope helpers for filtering
  scope :images, -> { where(media_type: 'images') }
  scope :audio, -> { where(media_type: 'audio') }
  scope :video, -> { where(media_type: 'video') }
  scope :fonts, -> { where(media_type: 'fonts') }
  scope :unused, -> {
      left_joins(:media_references)
        .where(media_references: { id: nil })
    }

  def self.remove_by_file_path(file_path)
    medium = find_by(file_path: file_path)
    medium&.destroy
  end

  private

  def normalize_media_type
    extension = media_type&.downcase

    case extension
    when 'png', 'jpg', 'jpeg', 'webp', 'gif', 'svg', 'bmp'
      self.media_type = 'images'
    when 'woff', 'woff2', 'ttf', 'otf'
      self.media_type = 'fonts'
    when 'mp3', 'm4a', 'wav', 'ogg', 'flac', 'aac'
      self.media_type = 'audio'
    when 'mp4', 'webm', 'ogv', 'mov', 'avi', 'mkv'
      self.media_type = 'video'
    end
  end
end
