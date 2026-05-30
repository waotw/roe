require "test_helper"

class MemberAuthenticationFlowTest < ActionDispatch::IntegrationTest
  def setup
    super

    @member = create(:member,
      name: "Test Member",
      email: "test@example.com",
      tier: :free,
      status: :active
    )

    # Create required pages for member flow
    create(:page,
      metadata: {
        "title" => "Sign In",
        "status" => "published",
        "url_name" => "sign-in"
      },
      content: "# Sign In\n\nPlease sign in to continue."
    )

    create(:page,
      metadata: {
        "title" => "Check Your Email",
        "status" => "published",
        "url_name" => "check-email"
      },
      content: "# Check Your Email\n\nWe've sent you a link."
    )
  end

  # ============================================================================
  # Magic Link Authentication Flow
  # ============================================================================

  test "complete magic link authentication flow" do
    # Step 1: Request sign-in link
    post "/signin", params: { member: { email: @member.email } }

    # Should redirect to check-email page
    assert_redirected_to "/check-email"

    # Token should be regenerated
    @member.reload
    old_token = @member.access_token
    assert_not_nil old_token

    # Step 2: Click magic link from email
    get "/signin/#{@member.access_token}"

    # Should be signed in and redirected to home
    assert_redirected_to "/"
    assert_equal @member.id, session[:member_id]
    assert_equal "Signed in successfully", flash[:notice]

    # Step 3: Access protected page (account)
    get "/account"
    assert_response :success
    assert_includes response.body, @member.name

    # Step 4: Sign out
    delete "/signout"
    assert_redirected_to "/"
    assert_nil session[:member_id]
    assert_equal "Signed out successfully", flash[:notice]
  end

  test "magic link fails for cancelled member" do
    cancelled_member = create(:member,
      name: "Cancelled Member",
      email: "cancelled@example.com",
      tier: :free,
      status: :cancelled
    )

    # Try to sign in with cancelled member token
    get "/signin/#{cancelled_member.access_token}"

    # Should be rejected
    assert_redirected_to "/signin"
    assert_equal "Invalid or expired link", flash[:alert]
    assert_nil session[:member_id]
  end

  test "magic link fails with invalid token" do
    get "/signin/invalid-token-12345"

    assert_redirected_to "/signin"
    assert_equal "Invalid or expired link", flash[:alert]
    assert_nil session[:member_id]
  end

  # ============================================================================
  # Session Persistence
  # ============================================================================

  test "session persists across requests" do
    # Sign in
    get "/signin/#{@member.access_token}"
    follow_redirect!

    # Make multiple requests
    get "/account"
    assert_response :success

    get "/account/edit"
    assert_response :success

    # Session should still be valid
    assert_equal @member.id, session[:member_id]
  end

  test "session survives page refreshes" do
    # Sign in
    get "/signin/#{@member.access_token}"
    follow_redirect!

    # Refresh account page multiple times
    3.times do
      get "/account"
      assert_response :success
      assert_equal @member.id, session[:member_id]
    end
  end

  # ============================================================================
  # Guest Access Restrictions
  # ============================================================================

  test "guest cannot access account pages" do
    # Try to access account as guest
    get "/account"

    # Should redirect to sign-in
    assert_redirected_to "/sign-in"
    assert_equal "Please sign in to continue", flash[:alert]
  end

  test "guest cannot edit account" do
    get "/account/edit"
    assert_redirected_to "/sign-in"
  end

  test "guest cannot update account" do
    patch "/account", params: { member: { name: "Hacked Name" } }
    assert_redirected_to "/sign-in"

    # Verify member was not changed
    @member.reload
    assert_equal "Test Member", @member.name
  end

  # ============================================================================
  # Token Security
  # ============================================================================

  test "token remains valid for session duration" do
    original_token = @member.access_token

    # Sign in
    get "/signin/#{original_token}"
    follow_redirect!

    # Token should not change on sign-in
    @member.reload
    assert_equal original_token, @member.access_token
  end

  test "token works for multiple sign-ins" do
    token = @member.access_token

    # First sign-in
    get "/signin/#{token}"
    follow_redirect!
    delete "/signout"
    follow_redirect!

    # Second sign-in with same token
    get "/signin/#{token}"
    follow_redirect!

    # Should work
    assert_equal @member.id, session[:member_id]
  end
end
