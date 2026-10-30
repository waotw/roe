require "test_helper"

# The Status dropdown filters in the browser and keeps its choice in the
# address (?status=). The server used to filter by that too, so after a
# refresh the page held only that status and switching the dropdown had
# nothing else to show. The page now always lists every member.
class Admin::MembersStatusFilterTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    stamp = SecureRandom.hex(4)
    @active = Member.create!(email: "active-#{stamp}@example.com", name: "Active", status: :active)
    @cancelled = Member.create!(email: "cancelled-#{stamp}@example.com", name: "Cancelled", status: :cancelled)
  end

  test "a page loaded with ?status= still lists every member" do
    get admin_members_path(status: "cancelled")

    assert_response :success
    assert_match @cancelled.email, response.body
    assert_match @active.email, response.body, "only cancelled members were sent, so the dropdown couldn't switch"
    # The dropdown still opens on the remembered choice.
    assert_select "select[data-members-filter-target=statusFilter] option[value=cancelled][selected]"
  end
end
