class ProcessPostmarkWebhookJob < ApplicationJob
  queue_as :default

  def perform(webhook_data)
    record_type = webhook_data["RecordType"]
    email = webhook_data["Recipient"] || webhook_data["Email"]

    return unless email.present?

    member = Member.find_by(email: email)

    unless member
      Rails.logger.info "Postmark webhook for non-existent member: #{email}"
      return
    end

    case record_type
    when "Bounce"
      handle_bounce(member, webhook_data)
    when "SpamComplaint"
      handle_spam_complaint(member, webhook_data)
    when "Delivery"
      handle_delivery(member, webhook_data)
    else
      Rails.logger.info "Unhandled Postmark webhook type: #{record_type}"
    end
  end

  private

  def handle_bounce(member, data)
    bounce_type = data["Type"]

    if bounce_type == "HardBounce"
      member.update!(newsletter_status: :bounced)
      Rails.logger.info "Member #{member.email} marked as bounced (#{data['Description']})"
    else
      # Track soft bounces
      metadata = member.metadata || {}
      count = (metadata["soft_bounce_count"] || 0) + 1
      metadata["soft_bounce_count"] = count
      metadata["last_soft_bounce_at"] = Time.current.iso8601

      if count >= 5
        # Too many soft bounces, treat as hard bounce
        member.update!(
          newsletter_status: :bounced,
          metadata: metadata
        )
        Rails.logger.warn "Member #{member.email} marked as bounced after #{count} soft bounces"
      else
        member.update!(metadata: metadata)
        Rails.logger.info "Soft bounce ##{count} for #{member.email}: #{data['Description']}"
      end
    end
  end

  def handle_spam_complaint(member, data)
    # MUST unsubscribe immediately for legal compliance
    member.update!(newsletter_status: :unsubscribed)
    Rails.logger.warn "Member #{member.email} marked as spam - unsubscribed"
  end

  def handle_delivery(member, data)
    # Just log successful delivery
    Rails.logger.info "Newsletter delivered to #{member.email}"
  end
end
