module PagesHelper
  def render_page_content(page)
    html = page.to_html

    # Replace token placeholders with actual tokens
    html = html.gsub('AUTHENTICITY_TOKEN_PLACEHOLDER', form_authenticity_token)

    # Replace member status placeholder with appropriate class
    member_status = current_member ? 'is-member' : 'is-guest'
    html = html.gsub('MEMBER_STATUS_PLACEHOLDER', member_status)

    # Truncate at paywall if user doesn't have access
    html = truncate_at_paywall(html, page) if should_truncate_content?(page)

    html.html_safe
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
      # Keep everything up to and including the gate
      html.split('<!-- PAID_CONTENT_GATE -->').first +
        html[/<!-- PAID_CONTENT_GATE -->.*?<\/div>/m].to_s
    else
      # No gate found - this shouldn't happen due to controller check
      html
    end
  end
end
