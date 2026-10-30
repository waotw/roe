require "test_helper"

# The recovery-codes copy affordance: clicking the codes block copies the
# exact newline-joined list (not a browser's mangled block selection) and
# flashes the Generate button to "Copied". This locks the server-rendered
# contract the Stimulus controller depends on; the JS itself has no harness.
class Members::RecoveryCopyWiringTest < ActionDispatch::IntegrationTest
  def setup
    super
    SiteFeature.stubs(:member_passwords_enabled?).returns(true)
    @member = create(:member, :active, email: "copy@example.com", name: "Copy")
    sign_in_member(@member)
  end

  test "fresh codes render the copy controller, targets, action, and exact text value" do
    post "/account/recovery-codes/regenerate"
    follow_redirect!
    body = response.body

    assert_includes body, 'data-controller="recovery-codes-copy"'
    assert_includes body, 'data-recovery-codes-copy-target="codes"'
    assert_includes body, 'data-recovery-codes-copy-target="feedback"'
    assert_includes body, "click->recovery-codes-copy#copy"

    text_value = body[/data-recovery-codes-copy-text-value="([^"]*)"/m, 1]
    assert_not_nil text_value, "codes block must carry the exact copy payload"

    # Payload is the canonical list: one code per line, no stray whitespace.
    lines = text_value.split("\n", -1)
    assert_equal Member::RECOVERY_CODE_COUNT, lines.size
    lines.each do |line|
      assert_equal line, line.strip, "no leading/trailing whitespace on a code line"
      assert_match(/\A[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}\z/, line)
    end
  end
end
