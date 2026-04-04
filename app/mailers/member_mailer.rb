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
end
