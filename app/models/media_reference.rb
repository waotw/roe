class MediaReference < ApplicationRecord
  belongs_to :post
  belongs_to :medium

  validates :post_id, uniqueness: { scope: :medium_id }
end
