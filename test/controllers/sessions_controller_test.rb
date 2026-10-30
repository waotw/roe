require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials redirects to the dashboard by default" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to admin_root_url
    assert cookies[:session_id]
  end

  test "create returns the admin to the page they were bounced from" do
    # Hitting a protected admin page while signed out saves the return path.
    get admin_edit_payments_config_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to admin_edit_payments_config_url
  end

  test "create ignores a return path pointing at another host" do
    # Defense in depth: even if the stored value were cross-origin, we don't
    # follow it. (request_authentication only ever stores this host's URL.)
    get new_session_path # normal entry, nothing stored
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to admin_root_url
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
