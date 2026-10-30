module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      return false if Current.static_generation
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
      Current.user ||= Current.session&.user
      Current.session
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      # Return the admin to the page they were trying to reach before we bounced
      # them to sign in (saved server-side in request_authentication, so it's
      # always this host's own URL — not a user-supplied param). Guard on
      # same-origin anyway as defense in depth, and fall back to the dashboard.
      target = session.delete(:return_to_after_authenticating)
      return admin_root_url if target.blank?

      begin
        uri = URI.parse(target)
        same_host = uri.host.nil? || uri.host == request.host
        return target if same_host && (uri.path.blank? || uri.path.start_with?("/"))
      rescue URI::InvalidURIError
        # fall through
      end
      admin_root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session&.destroy
      cookies.delete(:session_id)
    end
end
