require "test_helper"

class Members::AccountsControllerTest < ActionDispatch::IntegrationTest
  def setup
    super

    @free_member = create(:member,
      tier: :free,
      status: :active,
      name: "Test User",
      email: "test@example.com"
    )
    @paid_member = create(:member,
      tier: :paid,
      status: :active,
      name: "Paid User",
      email: "paid@example.com"
    )
  end

  # ============================================================================
  # Authentication Tests
  # ============================================================================

  test "redirects guest to signin for account page" do
    get "/account"
    assert_redirected_to "/sign-in"
    assert_equal "Please sign in to continue", flash[:alert]
  end

  test "redirects guest to signin for edit account" do
    get "/account/edit"
    assert_redirected_to "/sign-in"
  end

  test "redirects guest to signin for update account" do
    patch "/account", params: { member: { name: "New Name" } }
    assert_redirected_to "/sign-in"
  end

  # ============================================================================
  # Show Action Tests
  # ============================================================================

  test "shows account page for signed in member" do
    sign_in_member(@free_member)
    get "/account"

    assert_response :success
    assert_includes response.body, @free_member.name
    assert_includes response.body, @free_member.email
  end

  test "shows account page for paid member" do
    sign_in_member(@paid_member)
    get "/account"

    assert_response :success
    assert_includes response.body, @paid_member.name
  end

  test "account page shows member tier" do
    sign_in_member(@free_member)
    get "/account"

    assert_response :success
    assert_includes response.body.downcase, "free"
  end

  # ============================================================================
  # Edit Action Tests
  # ============================================================================

  test "shows edit form for member" do
    sign_in_member(@free_member)
    get "/account/edit"

    assert_response :success
    assert_select "form"
    assert_select "input[name='member[name]']"
    assert_select "input[name='member[email]']"
  end

  test "edit form pre-fills current values" do
    sign_in_member(@free_member)
    get "/account/edit"

    assert_response :success
    assert_includes response.body, @free_member.name
    assert_includes response.body, @free_member.email
  end

  # ============================================================================
  # Update Action Tests - Name Only
  # ============================================================================

  test "updates member name successfully" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: "Updated Name",
        email: @free_member.email # Keep same email
      }
    }

    assert_redirected_to "/account"
    assert_equal "Account updated successfully", flash[:notice]

    @free_member.reload
    assert_equal "Updated Name", @free_member.name
    assert_equal "test@example.com", @free_member.email
  end

  test "fails to update with blank name" do
    sign_in_member(@free_member)
    old_name = @free_member.name

    patch "/account", params: {
      member: {
        name: "",
        email: @free_member.email
      }
    }

    assert_response :unprocessable_entity
    assert_select "form" # Re-renders form

    @free_member.reload
    assert_equal old_name, @free_member.name
  end

  # ============================================================================
  # Update Action Tests - Email Change
  # ============================================================================

  test "initiates email change with confirmation" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: @free_member.name,
        email: "newemail@example.com"
      }
    }

    assert_redirected_to "/account"
    assert_match /confirmation email has been sent/, flash[:notice]

    @free_member.reload
    # Email should not change yet
    assert_equal "test@example.com", @free_member.email
    # Pending email should be set
    assert_equal "newemail@example.com", @free_member.pending_email
    # Confirmation token should be generated
    assert_not_nil @free_member.email_confirmation_token
  end

  test "does not send confirmation when email unchanged" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: "Updated Name",
        email: @free_member.email
      }
    }

    assert_redirected_to "/account"
    assert_equal "Account updated successfully", flash[:notice]

    # Should not have pending email
    @free_member.reload
    assert_nil @free_member.pending_email
  end

  test "handles email change to existing email" do
    existing_member = create(:member, email: "existing@example.com")
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: @free_member.name,
        email: "existing@example.com"
      }
    }

    # Should fail validation - email already taken
    assert_response :unprocessable_entity
    @free_member.reload
    # Original email should remain unchanged
    assert_equal "test@example.com", @free_member.email
  end

  test "prevents duplicate pending email between members" do
    member_a = create(:member, email: "member-a@example.com")
    member_b = create(:member, email: "member-b@example.com")

    # Member A starts changing to a new email
    sign_in_member(member_a)
    patch "/account", params: {
      member: {
        name: member_a.name,
        email: "new-shared@example.com"
      }
    }
    assert_redirected_to "/account"
    member_a.reload
    assert_equal "new-shared@example.com", member_a.pending_email
    sign_out_member

    # Member B tries to change to the same email
    sign_in_member(member_b)
    patch "/account", params: {
      member: {
        name: member_b.name,
        email: "new-shared@example.com"
      }
    }

    # Should fail - pending_email already taken by Member A
    assert_response :unprocessable_entity
    member_b.reload
    assert_nil member_b.pending_email
    assert_equal "member-b@example.com", member_b.email
  end

  # ============================================================================
  # Email Confirmation Tests
  # ============================================================================

  test "confirms email change with valid token" do
    sign_in_member(@free_member)
    @free_member.update!(
      pending_email: "newemail@example.com"
    )
    @free_member.generate_email_confirmation_token!
    token = @free_member.email_confirmation_token

    get confirm_email_path(token: token)

    assert_redirected_to "/account"
    assert_equal "Email address confirmed successfully!", flash[:notice]

    @free_member.reload
    assert_equal "newemail@example.com", @free_member.email
    assert_nil @free_member.pending_email
    assert_nil @free_member.email_confirmation_token
  end

  test "rejects invalid confirmation token" do
    sign_in_member(@free_member)
    @free_member.update!(pending_email: "newemail@example.com")
    @free_member.generate_email_confirmation_token!

    get confirm_email_path(token: "invalid_token")

    assert_redirected_to "/account"
    assert_equal "Invalid or expired confirmation link.", flash[:alert]

    @free_member.reload
    # Email should not change
    assert_equal "test@example.com", @free_member.email
  end

  test "rejects expired confirmation token" do
    sign_in_member(@free_member)
    @free_member.update!(
      pending_email: "newemail@example.com"
    )
    @free_member.generate_email_confirmation_token!
    token = @free_member.email_confirmation_token

    # Manually set the sent_at to make it expired (must be AFTER generate_token!)
    @free_member.update!(email_confirmation_sent_at: 25.hours.ago)

    get confirm_email_path(token: token)

    assert_redirected_to "/account"
    follow_redirect!
    assert_equal "Invalid or expired confirmation link.", flash[:alert]
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  test "handles simultaneous name and email update" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: "New Name",
        email: "newemail@example.com"
      }
    }

    # Both name and email change should be processed
    assert_redirected_to "/account"
    assert_match /confirmation email/, flash[:notice]

    @free_member.reload
    # Name should be updated immediately
    assert_equal "New Name", @free_member.name
    # Email should be pending confirmation
    assert_equal "newemail@example.com", @free_member.pending_email
    # Original email should remain until confirmation
    assert_equal "test@example.com", @free_member.email
  end

  test "member can view account after tier upgrade" do
    sign_in_member(@paid_member)
    get "/account"

    assert_response :success
    assert_includes response.body.downcase, "paid"
  end

  test "session persists across account page loads" do
    sign_in_member(@free_member)

    get "/account"
    assert_response :success

    get "/account"
    assert_response :success

    assert_equal @free_member.id, session[:member_id]
  end

  test "cancelled member cannot access account" do
    cancelled_member = create(:member, status: :cancelled)

    # Try to sign in (should fail)
    get "/signin/#{cancelled_member.access_token}"
    # Controller redirects to signin_path (/signin) first
    assert_redirected_to "/signin"
  end

  # ============================================================================
  # Security Tests
  # ============================================================================

  test "member cannot update another member's account" do
    member2 = create(:member, name: "Other Member", email: "other@example.com")

    sign_in_member(@free_member)

    # Try to update with different member's ID (if exposed)
    patch "/account", params: {
      member: {
        name: "Hacked Name"
      }
    }

    # Should only update current member
    @free_member.reload
    assert_equal "Hacked Name", @free_member.name

    member2.reload
    assert_equal "Other Member", member2.name
  end

  test "empty email is ignored and other fields update successfully" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: "Updated Name",
        email: ""
      }
    }

    # Empty email is ignored, name update succeeds
    assert_redirected_to "/account"
    assert_equal "Account updated successfully", flash[:notice]

    @free_member.reload
    # Email should remain unchanged
    assert_equal "test@example.com", @free_member.email
    # Name should be updated
    assert_equal "Updated Name", @free_member.name
  end

  test "CSRF protection is disabled in test environment" do
    # Note: CSRF protection is disabled in config/environments/test.rb
    # This is standard Rails practice for integration tests
    # Verify the form renders without needing authenticity token
    sign_in_member(@free_member)
    get "/account/edit"

    assert_response :success
    assert_select "form[action='/account']"
  end

  # ============================================================================
  # Form Validation Tests
  # ============================================================================

  test "handles very long names gracefully" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: "A" * 1000,
        email: @free_member.email
      }
    }

    # Should either accept or fail gracefully. Any redirect counts — the exact
    # code isn't the point, and a non-GET redirect is 303 now (see
    # ApplicationController#redirect_to).
    assert response.redirect? || response.status == 422,
      "expected a redirect or 422, got #{response.status}"
  end

  test "handles special characters in name" do
    sign_in_member(@free_member)

    patch "/account", params: {
      member: {
        name: "José María O'Connor-Smith",
        email: @free_member.email
      }
    }

    assert_redirected_to "/account"
    @free_member.reload
    assert_equal "José María O'Connor-Smith", @free_member.name
  end
end
