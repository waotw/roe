class Dispute < ApplicationRecord
  enum :status, { open: 0, closed: 1 }, prefix: true

  validates :stripe_dispute_id, presence: true, uniqueness: true
  validates :status, presence: true

  scope :currently_open, -> { where(status: :open) }
end
