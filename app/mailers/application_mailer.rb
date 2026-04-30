class ApplicationMailer < ActionMailer::Base
  default from: -> { SiteConfig.get('author_email').presence || "noreply@#{default_url_options[:host] || 'localhost'}" }
  layout "mailer"
end
