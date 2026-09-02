class NewsletterSend < ApplicationRecord
  belongs_to :post
  belongs_to :member
  belongs_to :import, optional: true

  # A row used to exist only when Postmark accepted a message, and the admin
  # panel counts rows — so forty failures out of a hundred read as "sent to 60
  # members" and the other forty lived only in a log nobody tails.
  #
  # Both outcomes are recorded here rather than in a separate failures table,
  # because everything that counts sends would then need a join, and the panel
  # that already miscounts is exactly what would get it wrong again.
  SENT   = "sent"
  FAILED = "failed"

  validates :post_id, presence: true
  validates :member_id, presence: true
  validates :status, inclusion: { in: [ SENT, FAILED ] }
  # Only a successful send has a sent_at; a failure records attempted_at.
  validates :sent_at, presence: true, if: :sent?
  validates :post_id, uniqueness: { scope: :member_id, message: "already sent to this member" }

  scope :sent,       -> { where(status: SENT) }
  scope :failed,     -> { where(status: FAILED) }
  scope :recent,     -> { order(sent_at: :desc) }
  scope :for_post,   ->(post) { where(post: post) }
  scope :for_member, ->(member) { where(member: member) }

  def sent?   = status == SENT
  def failed? = status == FAILED

  # A failure is worth retrying; a success isn't. Used by the job to decide who
  # still needs the newsletter, so a retry doesn't skip everyone who failed.
  def self.delivered_member_ids(post)
    sent.for_post(post).pluck(:member_id)
  end

  # Records an outcome for one member, replacing any earlier attempt — a member
  # who failed and then succeeds should end up marked sent, not carry both.
  def self.record!(post:, member:, message_id: nil, error: nil)
    row = find_or_initialize_by(post: post, member: member)
    if error
      row.assign_attributes(status: FAILED, error: error.to_s.truncate(500),
                            attempted_at: Time.current)
    else
      row.assign_attributes(status: SENT, error: nil, message_id: message_id,
                            sent_at: Time.current, attempted_at: Time.current)
    end
    row.save!
    row
  end
end
