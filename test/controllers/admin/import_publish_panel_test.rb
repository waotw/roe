# frozen_string_literal: true

require "test_helper"

# The publish panel had no test that rendered it, so a variable removed from its
# setup block while it was still used further down only surfaced when someone
# opened an import on a real install.
class Admin::ImportPublishPanelTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  # phase_completed?(4) is what puts the publish panel on the page, and the
  # status helpers read stats — an import missing either renders a page that
  # never reaches the partial under test.
  def import(stats: {})
    Import.create!(source_type: "substack", phase: 4, status: :completed,
                   completed_phases: [ 1, 2, 3, 4 ], stats: stats)
  end

  test "an import page renders when the peer has never been heard from" do
    # The case that broke: with no cached peer state the panel takes its
    # "haven't heard from live yet" branch, which reads a fingerprint.
    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_state).returns(nil)

    get admin_import_path(import)

    assert_response :success
  end

  test "an import page renders with no peer configured" do
    SiteSync::Exchange.stubs(:can_call_peer?).returns(false)

    get admin_import_path(import)

    assert_response :success
  end

  test "an import page renders when local and live agree" do
    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_state).returns({ fingerprint: "same", received_at: Time.current })
    SiteSync::Ledger.stubs(:fingerprint_for).returns("same")

    get admin_import_path(import)

    assert_response :success
  end

  test "a published import reports what was updated, not just inserted" do
    published = import(stats: {
      "published_to_live" => {
        "at" => Time.current.iso8601,
        "counts" => { "members_inserted" => 2, "members_updated" => 7, "members_skipped" => 1 },
        "follow_up" => { "lapsed_paid" => [ "lapsed@example.com" ] },
        "errors" => []
      }
    })

    get admin_import_path(published)

    assert_response :success
    assert_match(/7\s*updated/, response.body)
    assert_match "lapsed@example.com", response.body
    assert_match(/lapsed before this import/i, response.body)
  end
end
