# Renders a deploy message the way the page does, so a test can check what
# someone actually reads rather than a string held in Ruby. The wording lives
# in app/views/admin/deploy_messages/.
module DeployMessageHelper
  def deploy_message_html(key, context: :during, **locals)
    ApplicationController.render(
      partial: "admin/deploy_messages/message",
      locals: { key: key, context: context, **locals }
    )
  end

  # Plain text, with HTML entities decoded — "You're", not "You&#39;re".
  def deploy_message_text(key, **options)
    Nokogiri::HTML.fragment(deploy_message_html(key, **options)).text.squish
  end
end
