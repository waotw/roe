class QueueNewsletterBatchesJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 500  # 500 members per job, each job does batches of 100

  def perform(post_id, member_ids = nil)
    post = Post.find(post_id)

    # Get recipients: use provided IDs or calculate based on audience
    recipient_ids = if member_ids.present?
      # Resend to specific members (e.g., new members)
      member_ids
    else
      # Initial send - get all eligible recipients
      get_recipients(post).pluck(:id)
    end

    total = recipient_ids.size
    batches = recipient_ids.in_groups_of(BATCH_SIZE, false)

    Rails.logger.info "Queueing #{batches.size} batch jobs for #{total} recipients"

    batches.each do |batch_ids|
      SendNewsletterJob.perform_later(post_id, batch_ids)
    end
  end

  private

  def get_recipients(post)
    # Get all newsletter subscribers based on post audience
    members = Member.newsletter_subscribed.active

    # Filter by audience
    members = case post.audience
    when 'paid'
      members.paid_tier
    else
      members  # Everyone gets it
    end

    # Exclude members who already received this newsletter
    already_sent_ids = NewsletterSend.where(post: post).pluck(:member_id)
    members = members.where.not(id: already_sent_ids) if already_sent_ids.any?

    members
  end
end
