module Members
  class BaseController < ActionController::Base
    include MemberAuthentication

    layout "site"

    # Don't include Authentication concern - that's for admins only!

    # The site layout asks authenticated? to decide IS_ADMIN — an admin browsing
    # the public site still sees admin affordances. Member controllers skip the
    # admin Authentication concern (and its require_authentication before_action),
    # so provide a READ-ONLY resolver: read the admin session cookie the same way,
    # add nothing. Without it a member page rendered from here (e.g. a failed
    # sign-in re-rendering pages/show) raised NoMethodError on authenticated?.
    helper_method :authenticated?

    private

    def authenticated?
      return false if Current.static_generation
      Current.session ||= Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
      Current.session.present?
    end
  end
end
