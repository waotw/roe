module PostsHelper
  def format_duration(duration)
    # Handle both "HH:MM:SS" and seconds formats
    if duration.to_s.include?(':')
      duration # Already formatted
    else
      # Convert seconds to HH:MM:SS
      seconds = duration.to_i
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60

      if hours > 0
        "%d:%02d:%02d" % [hours, minutes, secs]
      else
        "%d:%02d" % [minutes, secs]
      end
    end
  end

  def render_post_content(post)
    html = post.to_html

    # Replace token placeholders
    html = html.gsub('AUTHENTICITY_TOKEN_PLACEHOLDER', form_authenticity_token)

    # Replace member status
    member_status = current_member ? 'is-member' : 'is-guest'
    html = html.gsub('MEMBER_STATUS_PLACEHOLDER', member_status)

    # Truncate at paywall if needed
    html = truncate_at_paywall(html, post) if should_truncate_content?(post)

    html.html_safe  # ← Return safe buffer from helper
  end

  private

  def should_truncate_content?(item)
    return false unless item.metadata['audience'] == 'paid'
    return false if current_member&.paid? && current_member&.active?
    return false if authenticated? # Admins can see everything

    true
  end

  def truncate_at_paywall(html, item)
    if html.include?('<!-- PAID_CONTENT_GATE -->')
      html.split('<!-- PAID_CONTENT_GATE -->').first +
        html[/<!-- PAID_CONTENT_GATE -->.*?<\/div>/m].to_s
    else
      html
    end
  end
end
