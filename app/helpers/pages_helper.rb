module PagesHelper
  def render_page_content(page)
    html = page.to_html

    # Replace token placeholders with actual tokens
    html = html.gsub('AUTHENTICITY_TOKEN_PLACEHOLDER', form_authenticity_token)

    # Replace member status placeholder with appropriate class
    member_status = current_member ? 'is-member' : 'is-guest'
    html = html.gsub('MEMBER_STATUS_PLACEHOLDER', member_status)

    # Truncate at paywall if needed, or strip the gate entirely for paid members
    if should_truncate_content?(page)
      html = truncate_at_paywall(html, page)
    else
      html = strip_paywall_gate(html)
    end

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

  def strip_paywall_gate(html)
    # Remove the gate comment and its div entirely for paid members/admins
    html.gsub(/<!-- PAID_CONTENT_GATE -->.*?<\/div>/m, '')
  end
end
