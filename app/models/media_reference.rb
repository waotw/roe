class MediaReference < ApplicationRecord
  # Polymorphic since posts, pages and products all reference media. It was
  # posts-only, which made a paid page's audio look unreferenced — and so
  # public.
  belongs_to :referenceable, polymorphic: true
  belongs_to :medium

  validates :medium_id, uniqueness: { scope: [ :referenceable_type, :referenceable_id ] }
end
