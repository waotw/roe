require "test_helper"

# Postmark "account pending approval" (ErrorCode 412): a real send to an outside
# domain is refused until Postmark approves the account. Roe captures that from
# the live send, surfaces it to the operator, and clears it once a send succeeds.
class PostmarkAccountApprovalTest < ActiveSupport::TestCase
  setup do
    PostmarkConfig.delete_all
    @pm = PostmarkConfig.current
  end

  test "account_pending_approval? is false until a 412 is recorded" do
    assert_not @pm.account_pending_approval?
  end

  test "record_account_pending_approval! sets the flag with Postmark's message" do
    @pm.record_account_pending_approval!("pending approval, same domain only")
    assert @pm.reload.account_pending_approval?
    assert_match(/pending approval/, @pm.account_approval_error)
  end

  test "clear_account_pending_approval! drops the flag" do
    @pm.record_account_pending_approval!("x")
    @pm.clear_account_pending_approval!
    assert_not @pm.reload.account_pending_approval?
  end

  test "the approval constant matches Postmark's code" do
    assert_equal 412, PostmarkConfig::ACCOUNT_PENDING_APPROVAL
  end

  test "disconnect! clears a pending-approval flag" do
    @pm.update!(server_token: "tok")
    @pm.record_account_pending_approval!("x")
    @pm.disconnect!
    assert_not @pm.reload.account_pending_approval?
  end

  # ── Status row ─────────────────────────────────────────────────────────────

  test "status shows no approval row until a 412 is caught" do
    @pm.update!(server_token: "tok")
    assert_nil PostmarkStatus.for(@pm).find { |i| i.key == :account_approval }
  end

  test "status shows the approval row with a same-domain test hint once flagged" do
    @pm.update!(server_token: "tok")
    @pm.record_account_pending_approval!("pending")
    SiteConfig.stubs(:get).returns(nil)
    SiteConfig.stubs(:get).with("author_email").returns("ben@weareontheweb.com")

    row = PostmarkStatus.for(@pm).find { |i| i.key == :account_approval }
    assert_equal :todo, row.state
    assert_match(/not approved/i, row.label)
    assert_match(/@weareontheweb\.com/, row.detail)
  end
end
