module PagesHelper
  def render_page_content(page, context: nil)
    html = page.to_html(context: context, preview: editor_preview?, static: @static_generation)

    # Replace token placeholders with actual tokens
    html = html.gsub("AUTHENTICITY_TOKEN_PLACEHOLDER", form_authenticity_token)

    # Replace member status placeholder with appropriate class
    member_status = current_member ? "is-member" : "is-guest"
    html = html.gsub("MEMBER_STATUS_PLACEHOLDER", member_status)

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
    return false unless item.audience == "paid"
    return false if current_member&.paid? && current_member&.active?
    return false if authenticated? # Admins can see everything

    true
  end

  def truncate_at_paywall(html, item)
    if html.include?("<!-- PAID_CONTENT_GATE -->")
      # Keep everything up to and including the gate
      html.split("<!-- PAID_CONTENT_GATE -->").first +
        html[/<!-- PAID_CONTENT_GATE -->.*?<\/div>/m].to_s
    else
      # No gate found - this shouldn't happen due to controller check
      html
    end
  end

  def strip_paywall_gate(html)
    # Paid members/admins see everything, so the gate is removed entirely.
    # When the gate split a list in two (a paywall in the middle of an
    # ordered/unordered list), merge the halves back into one list first —
    # otherwise the second <ol> restarts at 1. This joins them so the list
    # renders continuously, as if the paywall had never been there. Done
    # before the plain strip so the gate marker is still there to key off.
    html = merge_paywall_split_lists(html)
    html.gsub(/<!-- PAID_CONTENT_GATE -->.*?<\/div>/m, "")
  end

  # Join a list that a paid-content gate split into two same-type lists by
  # dropping the closing tag, gate, and reopening tag between them. The \1
  # backreference keeps ol↔ol and ul↔ul from cross-merging.
  def merge_paywall_split_lists(html)
    html.gsub(%r{</(ol|ul)>\s*<!-- PAID_CONTENT_GATE -->.*?</div>\s*<\1[^>]*>}m, "")
  end
end
