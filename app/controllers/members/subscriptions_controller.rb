module Members
  class SubscriptionsController < BaseController
    skip_before_action :set_current_member, only: [:unsubscribe, :confirm_unsubscribe]

    def unsubscribe
      @member = Member.find_by(access_token: params[:token])

      unless @member
        render plain: "Invalid unsubscribe link", status: :not_found
        return
      end

      # Query JSON metadata for url_name
      @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", 'unsubscribe')

      if @page
        render template: 'pages/show', layout: 'site'
      else
        render plain: "Unsubscribe page not found", status: :not_found
      end
    end

    def confirm_unsubscribe
      @member = Member.find_by(access_token: params[:token])

      unless @member
        render plain: "Invalid unsubscribe link", status: :not_found
        return
      end

      @member.unsubscribe_from_newsletter!

      # Redirect to unsubscribed success page
      redirect_to "/unsubscribed"
    end
  end
end
