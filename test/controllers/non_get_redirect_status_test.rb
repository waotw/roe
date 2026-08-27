# frozen_string_literal: true

require "test_helper"

# Rails redirects with 302 by default, which preserves the request method for
# everything except POST. A refused PATCH is therefore re-issued as a PATCH to
# wherever it was sent — and if that route is also non-GET, it redirects again.
#
# It stayed hidden because Rails forms send POST with a _method field, and 302
# does downgrade POST to GET. Only a real PATCH or DELETE loops.
class NonGetRedirectStatusTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def a_member(email = "nonget@example.com")
    Member.create!(email: email, name: "NG", tier: :free, status: :active)
  end

  test "a redirect after PATCH is 303, so the client follows up with GET" do
    m = a_member
    patch cancel_membership_admin_member_path(m)

    assert_response :see_other
    assert_redirected_to admin_member_path(m)
  end

  test "a redirect after DELETE is 303 too" do
    m = a_member("del@example.com")
    delete admin_member_path(m)

    assert_response :see_other
  end

  test "a redirect after POST is 303" do
    post admin_dismiss_site_transfer_status_path

    assert_response :see_other
  end

  # GET redirects are untouched — nothing about them was broken.
  test "a redirect after GET keeps the default 302" do
    m = a_member("get@example.com")
    m.anonymize!

    get edit_admin_member_path(m)

    assert_response :found, "a GET redirect shouldn't have changed"
  end

  # An explicit status on an individual redirect still wins.
  test "an explicit status is not overridden" do
    source = File.read(Rails.root.join("app", "controllers", "application_controller.rb"))
    body = source[/def redirect_to.*?^  end/m]

    assert_match(/response_options\.key\?\(:status\)/, body,
      "the override must defer to a caller that set one")
  end

  # The loop this closes: refuse a PATCH, land on the page, read the reason.
  test "a refused non-GET request lands somewhere that renders" do
    m = a_member("loop@example.com")
    m.update!(tier: :paid, paid_at: 1.week.ago, paid_amount_cents: 5000)
    m.anonymize!

    patch upgrade_to_paid_admin_member_path(m)
    follow_redirect!

    assert_response :success
    assert_match(/This account was deleted/, flash[:alert].to_s)
  end
end
