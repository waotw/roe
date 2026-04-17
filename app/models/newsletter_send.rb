class NewsletterSend < ApplicationRecord
  belongs_to :post
  belongs_to :member
  belongs_to :import, optional: true

  validates :post_id, presence: true
  validates :member_id, presence: true
  validates :sent_at, presence: true
  validates :post_id, uniqueness: { scope: :member_id, message: "already sent to this member" }

  scope :recent, -> { order(sent_at: :desc) }
  scope :for_post, ->(post) { where(post: post) }
  scope :for_member, ->(member) { where(member: member) }
end
