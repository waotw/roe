module AdminTitleHelper
  # The browser tab's title for an admin page: "Roe - <site> - <page>".
  # The page is the view's own `content_for :title` when it sets one, else
  # its first <h1>, so every page gets a name without each view repeating
  # its heading. A heading's badges (the Orders page's mode) are left out.
  def admin_page_title(body)
    page = content_for?(:title) ? content_for(:title) : first_heading(body)
    [ "Roe", SiteConfig.get("title").presence, page.to_s.squish.presence ].compact.uniq.join(" - ")
  end

  # Text of the first <h1>, without its nested elements. A pattern rather
  # than a parser: the Media page's body runs to megabytes.
  def first_heading(body)
    inner = body.to_s[%r{<h1\b[^>]*>(.*?)</h1>}m, 1]
    return nil unless inner

    text = inner.gsub(%r{<(\w+)\b[^>]*>.*?</\1>}m, "").gsub(/<[^>]*>/, "")
    CGI.unescapeHTML(text).squish.presence
  end
end
