class UpdateStatus < ApplicationRecord
  validates :status, presence: true, inclusion: { in: %w[pending in_progress awaiting_ruby completed failed rolled_back] }
  validates :from_version, presence: true
  validates :to_version, presence: true
end
