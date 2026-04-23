class FallbackMailer < ApplicationMailer
  default from: -> { SiteConfig.get('author_email').presence || 'noreply@example.com' }

  def generic(to:, subject:, html_content:)
    mail(
      to: to,
      subject: subject
    ) do |format|
      format.html { render html: html_content.html_safe }
    end
  end
end
