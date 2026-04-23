class MemberMailer
  class << self
    def magic_link(member)
      site_name = SiteConfig.get('title') || 'the site'
      signin_url = Rails.application.routes.url_helpers.token_signin_url(
        member.access_token,
        host: site_url
      )

      html_body = EmailRenderer.render('magic_link', {
        member_name: member.name || 'there',
        member_email: member.email,
        magic_link: signin_url,
        site_name: site_name
      })

      send_email(
        to: member.email,
        to_name: member.name || member.email,
        subject: "Sign in to #{site_name}",
        html_content: html_body
      )
    end

    def email_confirmation(member)
      site_name = SiteConfig.get('title') || 'the site'
      confirmation_url = Rails.application.routes.url_helpers.confirm_email_url(
        token: member.email_confirmation_token,
        host: site_url
      )

      html_body = EmailRenderer.render('email_confirmation', {
        member_name: member.name || 'there',
        member_email: member.pending_email,
        confirmation_url: confirmation_url,
        site_name: site_name
      })

      send_email(
        to: member.pending_email,
        to_name: member.name || member.email,
        subject: "Confirm your email address",
        html_content: html_body
      )
    end

    def welcome(member)
      site_name = SiteConfig.get('title') || 'the site'

      html_body = EmailRenderer.render('welcome', {
        member_name: member.name || 'there',
        member_email: member.email,
        site_name: site_name
      })

      send_email(
        to: member.email,
        to_name: member.name || member.email,
        subject: "Welcome to #{site_name}!",
        html_content: html_body
      )
    end

    def upgrade_success(member, password)
      site_name = SiteConfig.get('title') || 'the site'
      account_url = Rails.application.routes.url_helpers.account_url(host: site_url)

      html_body = EmailRenderer.render('upgrade_success', {
        member_name: member.name || 'there',
        member_email: member.email,
        password: password,
        site_name: site_name,
        account_url: account_url
      })

      send_email(
        to: member.email,
        to_name: member.name || member.email,
        subject: "Your #{site_name} membership is active!",
        html_content: html_body
      )
    end

    def email_changed(member, old_email)
      site_name = SiteConfig.get('title') || 'the site'

      html_body = EmailRenderer.render('email_changed', {
        member_name: member.name || 'there',
        new_email: member.email,
        old_email: old_email,
        site_name: site_name
      })

      # Send to BOTH old and new email for security
      [ old_email, member.email ].each do |email|
        send_email(
          to: email,
          to_name: member.name || email,
          subject: "Your #{site_name} email has been changed",
          html_content: html_body
        )
      end
    end

    def membership_cancelled(member)
      site_name = SiteConfig.get('title') || 'the site'

      html_body = EmailRenderer.render('membership_cancelled', {
        member_name: member.name || 'there',
        member_email: member.email,
        site_name: site_name
      })

      send_email(
        to: member.email,
        to_name: member.name || member.email,
        subject: "Your #{site_name} membership has been cancelled",
        html_content: html_body
      )
    end

    def payment_failed(member)
      site_name = SiteConfig.get('title') || 'the site'
      update_payment_url = Rails.application.routes.url_helpers.account_url(host: site_url)

      html_body = EmailRenderer.render('payment_failed', {
        member_name: member.name || 'there',
        member_email: member.email,
        update_payment_url: update_payment_url,
        site_name: site_name
      })

      send_email(
        to: member.email,
        to_name: member.name || member.email,
        subject: "Payment failed for your #{site_name} membership",
        html_content: html_body
      )
    end

    def account_deletion(member)
      site_name = SiteConfig.get('title') || 'the site'

      html_body = EmailRenderer.render('account_deletion', {
        member_name: member.name || 'there',
        member_email: member.email,
        site_name: site_name
      })

      send_email(
        to: member.email,
        to_name: member.name || member.email,
        subject: "Your #{site_name} account has been deleted",
        html_content: html_body
      )
    end

    private

    def send_email(to:, to_name:, subject:, html_content:)
      Rails.logger.info "🔍 Attempting to send email to #{to}"
      Rails.logger.info "📧 Subject: #{subject}"

      postmark_config = PostmarkConfig.current
      postmark_configured = PostmarkConfig.exists? && PostmarkConfig.current.connected?

      if postmark_configured
        result = PostmarkService.send_transactional_email(
          to_email: to,
          to_name: to_name,
          subject: subject,
          html_content: html_content,
          tag: 'member-email'
        )

        Rails.logger.info "📬 Result: #{result.inspect}"

        if result[:success]
          Rails.logger.info "✉️  Sent '#{subject}' to #{to} (Message ID: #{result[:message_id]})"
        else
          Rails.logger.error "❌ Failed to send email to #{to}: #{result[:error]}"
        end

        result
      else
        # Postmark not configured — fall back to Rails ActionMailer (letter_opener in dev)
        Rails.logger.info "📬 Postmark not configured, falling back to ActionMailer"
        FallbackMailer.generic(to: to, subject: subject, html_content: html_content).deliver_now
        { success: true, fallback: true }
      end
    end

    def site_url
      SiteConfig.site_url
    end
  end
end
