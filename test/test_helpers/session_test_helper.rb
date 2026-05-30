module SessionTestHelper
  def sign_in_as(user)
    if user.is_a?(Member)
      # Member authentication uses session[:member_id]
      post "/signin/#{user.access_token}"
      follow_redirect! if response.redirect?
    else
      # Admin user authentication
      Current.session = user.sessions.create!

      ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
        cookie_jar.signed[:session_id] = Current.session.id
        cookies["session_id"] = cookie_jar[:session_id]
      end
    end
  end

  def sign_out
    if session[:member_id].present?
      # Member sign out
      delete "/signout"
    elsif Current.session.present?
      # Admin sign out
      Current.session&.destroy!
      cookies.delete("session_id")
    end
  end

  def sign_in_member(member)
    # Set the session directly to authenticate the member
    # This is the most reliable way in integration tests
    get "/signin/#{member.access_token}"
    follow_redirect! if response.redirect?
  end

  def current_member
    Member.find_by(id: session[:member_id])
  end

  def sign_out_member
    delete "/signout"
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
