class Medium < ApplicationRecord
  def self.remove_by_file_path(file_path)
    medium = find_by(file_path: file_path)
    medium&.destroy
  end
end
