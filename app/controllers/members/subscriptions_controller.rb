module Members
  class SubscriptionsController < BaseController
    include RateLimited

    skip_before_action :set_current_member, only: [ :unsubscribe, :confirm_unsubscribe ]

    # Token guessing, keyed on the IP for want of anything narrower. Someone
    # unsubscribing from their own newsletter clicks once.
    limit_requests :token, only: [ :unsubscribe, :confirm_unsubscribe ], with: -> {
      redirect_to root_path, alert: "Too many attempts. Try again shortly."
    }

    def unsubscribe
      @member = Member.find_by(access_token: params[:token])

      unless @member
        render plain: "Invalid unsubscribe link", status: :not_found
        return
      end

      # Query JSON metadata for url_name
      @page = Page.find_by("json_extract(metadata, '$.url_name') = ?", "unsubscribe")

      if @page
        render template: "pages/show", layout: "site"
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
