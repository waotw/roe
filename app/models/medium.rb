class Medium < ApplicationRecord
  before_save :normalize_media_type

  def self.remove_by_file_path(file_path)
    medium = find_by(file_path: file_path)
    medium&.destroy
  end

  private

    def normalize_media_type
      # Normalize image extensions to 'images'
      if %w[png jpg jpeg webp gif svg bmp].include?(media_type&.downcase)
        self.media_type = 'images'
      elsif %w[woff woff2 ttf otf].include?(media_type&.downcase)
        self.media_type = 'fonts'
      end
    end
end
