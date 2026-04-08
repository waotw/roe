class NewsletterSender
  attr_reader :post, :errors, :results

  def initialize(post)
    @post = post
    @errors = []
    @results = { sent: 0, failed: 0, skipped: 0, total: 0 }
  end

  # Main method: send newsletter to appropriate audience
  def send_to_audience
    # Validate prerequisites
    unless valid_for_sending?
      return {
        success: false,
        error: @errors.first,
        sent: 0,
        failed: 0,
        skipped: 0,
        total: 0
      }
    end

    # Get recipients
    recipients = get_recipients
    @results[:total] = recipients.count

    # Send to each recipient
    recipients.find_each do |member|
      send_to_member(member)
    end

    # Return results
    {
      success: @results[:failed] == 0,
      sent: @results[:sent],
      failed: @results[:failed],
      skipped: @results[:skipped],
      total: @results[:total],
      errors: @errors
    }
  end

  private

  def valid_for_sending?
    # Check if newsletters enabled
    unless newsletters_enabled?
      @errors << "Newsletter feature is not enabled"
      return false
    end

    # Check if Mailjet configured
    unless MailjetConfig.configured?
      @errors << "Mailjet is not configured"
      return false
    end

    # Check if post should be sent to newsletter
    published_to = post.metadata['published_to'] || post.published_to
    unless published_to.in?(['newsletter', 'both'])
      @errors << "Post is not published to newsletter (published_to: #{published_to})"
      return false
    end

    # Check if post is published
    unless post.published?
      @errors << "Post must be published before sending newsletter"
      return false
    end

    true
  end

  def newsletters_enabled?
    SiteConfig.default('members', 'newsletter')&.dig('enabled') == true
  rescue
    false
  end

  def members_enabled?
    SiteConfig.default('members', 'newsletter').present?
  rescue
    false
  end

  def get_recipients
    # Start with subscribed, active members
    members = Member.newsletter_subscribed.status_active

    # Filter by audience
    audience = post.metadata['audience'] || 'everyone'
    case audience
    when 'paid'
      members = members.tier_paid
    when 'everyone'
      # All subscribed members
    else
      # Default to everyone
    end

    # Exclude members who already received this newsletter
    already_sent_ids = NewsletterSend.where(post: post).pluck(:member_id)
    members = members.where.not(id: already_sent_ids)

    members
  end

  def send_to_member(member)
    # Double-check not already sent (race condition protection)
    if NewsletterSend.exists?(post: post, member: member)
      @results[:skipped] += 1
      Rails.logger.info "Skipped #{member.email} - already received newsletter for post #{post.id}"
      return
    end

    # Render newsletter HTML
    renderer = NewsletterRenderer.new(post)
    html_content = renderer.render

    # Send via Mailjet
    result = MailjetService.send_newsletter(
      to_email: member.email,
      to_name: member.name,
      subject: post.title || 'Newsletter',
      html_content: html_content
    )

    if result[:success]
      # Record the send
      NewsletterSend.create!(
        post: post,
        member: member,
        sent_at: Time.current,
        mailjet_message_id: result[:message_id]
      )
      @results[:sent] += 1
      Rails.logger.info "✓ Sent newsletter to #{member.email} (post: #{post.id})"
    else
      @results[:failed] += 1
      @errors << { member: member.email, error: result[:error] }
      Rails.logger.error "✗ Failed to send to #{member.email}: #{result[:error]}"
    end

  rescue => e
    @results[:failed] += 1
    @errors << { member: member.email, error: e.message }
    Rails.logger.error "✗ Exception sending to #{member.email}: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
