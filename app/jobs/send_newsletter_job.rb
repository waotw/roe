class SendNewsletterJob < ApplicationJob
  queue_as :default

  BULK_BATCH_SIZE = 50
  MAX_RETRIES = 3

  def perform(post_id, member_ids)
    post = Post.find(post_id)
    members = Member.where(id: member_ids)

    members_to_send = members.reject { |m| NewsletterSend.exists?(post: post, member: m) }

    Rails.logger.info "Sending to #{members_to_send.size} members for post #{post_id}"

    return { sent: 0, failed: 0 } if members_to_send.empty?

    # Render newsletter once
    renderer = NewsletterRenderer.new(post)
    html_content = renderer.render
    from_email = SiteConfig.current('site')&.config&.dig('author_email') || 'noreply@example.com'
    from_name = SiteConfig.current('site')&.config&.dig('author') || 'Newsletter'

    # Build messages array with member association
    messages_with_members = members_to_send.map do |member|
      message = {
        From: { Email: from_email, Name: from_name },
        To: [{ Email: member.email, Name: member.name }],
        Subject: post.title || 'Newsletter',
        HTMLPart: html_content,
        TextPart: strip_html(html_content),
        CustomID: "post_#{post.id}_member_#{member.id}"
      }
      [member, message]  # Return [member, message] tuple
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

          if msg_result['Status'] == 'success'
            message_id = msg_result.dig('To', 0, 'MessageID')

            # Use find_or_create_by to avoid duplicates
            NewsletterSend.find_or_create_by!(post: post, member: member) do |ns|
              ns.sent_at = Time.current
              ns.mailjet_message_id = message_id
            end

            sent_count += 1
          else
            failed_count += 1
            Rails.logger.error "Failed to send to #{member.email}: #{msg_result.inspect}"
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

    { sent: sent_count, failed: failed_count }
  end

  private

  def send_batch_with_retry(batch, attempt = 1)
    result = MailjetService.send_newsletter_bulk(messages: batch)

    if !result[:success] && result[:error].to_s.include?('429')
      if attempt <= MAX_RETRIES
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
