class QueueNewsletterBatchesJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 500  # 500 members per job, each job does 10 bulk API calls of 50

  def perform(post_id)
    post = Post.find(post_id)

    sender = NewsletterSender.new(post)
    recipient_ids = sender.send(:get_recipients).pluck(:id)

    total = recipient_ids.size
    batches = recipient_ids.in_groups_of(BATCH_SIZE, false)

    Rails.logger.info "Queueing #{batches.size} batch jobs for #{total} recipients"

    batches.each do |batch_ids|
      SendNewsletterJob.perform_later(post_id, batch_ids)
    end
  end
end
