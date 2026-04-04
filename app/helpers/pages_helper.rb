module PagesHelper

  def render_page_content(page)
    html = page.to_html

    # Replace token placeholders with actual tokens
    html.gsub('AUTHENTICITY_TOKEN_PLACEHOLDER', form_authenticity_token)
  end
end
