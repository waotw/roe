class MemberMailer < ApplicationMailer
  def magic_link(member)
    @member = member
    signin_url = token_signin_url(member.access_token)
    site_name = SiteConfig.get('title') || 'the site'

    html_body = EmailRenderer.render('magic_link', {
      site_title: site_name,
      member_name: member.name || 'there',
      signin_url: signin_url
    })

    mail(
      to: member.email,
      subject: "Sign in to #{site_name}"
    ) do |format|
      format.html { render html: html_body.html_safe }
    end
  end

  def email_confirmation(member)
    @member = member
    confirmation_url = confirm_email_url(token: member.email_confirmation_token)
    site_name = SiteConfig.get('title') || 'the site'

    html_body = EmailRenderer.render('email_confirmation', {
      member_name: member.name || 'there',
      confirmation_url: confirmation_url
    })

    mail(
      to: member.pending_email,
      subject: "Confirm your email address"
    ) do |format|
      format.html { render html: html_body.html_safe }
    end
  end
end
