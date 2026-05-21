class SendNewsletterJob < ApplicationJob
  queue_as :default

  BULK_BATCH_SIZE = 100
  MAX_RETRIES = 3

  def perform(post_id, member_ids)
    post = Post.find(post_id)
    members = Member.where(id: member_ids)

    members_to_send = members.reject { |m| NewsletterSend.exists?(post: post, member: m) }

    Rails.logger.info "Sending to #{members_to_send.size} members for post #{post_id}"

    return { sent: 0, failed: 0 } if members_to_send.empty?

    from_email = SiteConfig.current('site')&.config&.dig('author_email') || 'noreply@example.com'
    from_name = SiteConfig.current('site')&.config&.dig('author') || 'Newsletter'

    # Build messages array with member association
    messages_with_members = members_to_send.map do |member|
      # Render newsletter WITH member-specific unsubscribe link
      renderer = NewsletterRenderer.new(post, member)
      html_content = renderer.render

      message = {
        From: "#{from_name} <#{from_email}>",
        To: "#{member.name} <#{member.email}>",
        Subject: post.title || 'Newsletter',
        HtmlBody: html_content,
        TextBody: strip_html(html_content),
        MessageStream: 'broadcast',
        Tag: 'newsletter',
        Metadata: {
          post_id: post.id.to_s,
          member_id: member.id.to_s
        }
      }
      [member, message]
    end

    # Send in bulk batches
    sent_count = 0
    failed_count = 0

    messages_with_members.each_slice(BULK_BATCH_SIZE).with_index do |batch_tuples, batch_index|
      batch_members = batch_tuples.map(&:first)
      batch_messages = batch_tuples.map(&:last)

      result = send_batch_with_retry(batch_messages)

      if result[:success]
        # Process results with correct member mapping
        result[:results].each_with_index do |msg_result, index|
          member = batch_members[index]

          if msg_result['ErrorCode'] == 0
            message_id = msg_result['MessageID']

            # Use find_or_create_by to avoid duplicates
            NewsletterSend.find_or_create_by!(post: post, member: member) do |ns|
              ns.sent_at = Time.current
              ns.message_id = message_id
            end

            sent_count += 1
          else
            failed_count += 1
            Rails.logger.error "Failed to send to #{member.email}: #{msg_result['Message']}"
          end
        end
      else
        failed_count += batch_tuples.size
        Rails.logger.error "Bulk batch #{batch_index} failed: #{result[:error]}"
      end

      # Pause between batches
      sleep(0.2) unless batch_index == (messages_with_members.size / BULK_BATCH_SIZE).floor
    end

    Rails.logger.info "Batch complete for post #{post_id}: #{sent_count} sent, #{failed_count} failed"

    # Broadcast update to refresh newsletter status
    broadcast_newsletter_status(post)

    { sent: sent_count, failed: failed_count }
  end

  private

  def broadcast_newsletter_status(post)
    Turbo::StreamsChannel.broadcast_replace_to(
      "post_#{post.id}_newsletter_status",
      target: "newsletter-status-#{post.id}",
      partial: "admin/posts/newsletter_status",
      locals: { post: post }
    )
  rescue => e
    Rails.logger.error "Failed to broadcast newsletter status: #{e.message}"
  end

  def send_batch_with_retry(batch, attempt = 1)
    result = PostmarkService.send_newsletter_batch(messages: batch)

    # Postmark returns 429 for rate limiting (though rare)
    if !result[:success] && result[:error].to_s.include?('429')
      if attempt < MAX_RETRIES
        wait_time = 2 ** attempt
        Rails.logger.warn "Rate limited (429), waiting #{wait_time}s before retry #{attempt}/#{MAX_RETRIES}"
        sleep(wait_time)
        return send_batch_with_retry(batch, attempt + 1)
      else
        Rails.logger.error "Rate limit retry exhausted after #{MAX_RETRIES} attempts"
      end
    end

    result
  end

  def strip_html(html)
    html.gsub(/<[^>]*>/, '').gsub(/\s+/, ' ').strip
  end
end
