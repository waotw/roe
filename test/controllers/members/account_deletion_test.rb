# frozen_string_literal: true

require "test_helper"

# Deleting an account from the member's own page. The model test covers what
# survives; this covers the door — that it needs the typed word, that it ends
# the session, and that the links a deleted member held stop working.
class Members::AccountDeletionTest < ActionDispatch::IntegrationTest
  # Stated here rather than inherited from whatever wrote a members.yml into
  # the shared test site earlier in the run.
  setup { SiteFeature.stubs(:members_enabled?).returns(true) }

  def member
    @member ||= Member.create!(email: "gone@example.com", name: "Gone",
                               tier: :paid, status: :active)
  end

  def sign_in
    get "/signin/#{member.access_token}"
  end

  test "the account page offers deletion" do
    sign_in
    get "/account"

    assert_response :success
    assert_match "Delete my account", response.body
    assert_match "Type <strong>DELETE</strong> to confirm", response.body
  end

  # The word is the whole safeguard. Anything else has to be a no-op, or the
  # safeguard is decoration.
  test "an empty or wrong confirmation deletes nothing" do
    sign_in

    [ "", "delete my account", "yes", "DELETED" ].each do |wrong|
      delete "/account", params: { confirm: wrong }

      assert_redirected_to "/account"
      assert_not member.reload.status_deleted?, "#{wrong.inspect} should not delete"
    end
  end

  test "typing DELETE deletes the account" do
    sign_in
    delete "/account", params: { confirm: "DELETE" }

    assert_redirected_to "/"
    # reset_session before setting a flash is the classic way to lose it, and
    # a silent redirect home reads like the deletion failed.
    assert_match(/deleted/i, flash[:notice].to_s)
    member.reload
    assert member.status_deleted?
    assert_equal "Deleted account", member.name
  end

  # Case and stray whitespace are the shape of a real person typing into a box,
  # not a different intent.
  test "case and whitespace don't matter" do
    sign_in
    delete "/account", params: { confirm: "  delete " }

    assert member.reload.status_deleted?
  end

  test "they're signed out, not left on a page for an account that's gone" do
    sign_in
    delete "/account", params: { confirm: "DELETE" }

    get "/account"
    assert_response :redirect
    assert_no_match "gone@example.com", response.body
  end

  # The old magic link is in their inbox. It must not let them back in.
  test "their old sign-in link is dead" do
    old_token = member.access_token
    sign_in
    delete "/account", params: { confirm: "DELETE" }

    get "/signin/#{old_token}"
    get "/account"

    assert_response :redirect, "the old link signed a deleted member back in"
  end

  test "signed out, nobody can delete an account" do
    assert_no_difference -> { Member.status_deleted.count } do
      delete "/account", params: { confirm: "DELETE" }
    end

    assert_response :redirect
  end
end
