# frozen_string_literal: true

require "test_helper"

# A Roe update brings newer themes and site scripts but never installs them:
# the site owns its copies, and they're offered on the Themes page. These two
# signs point there — a dot on the Themes nav link on every admin page, and a
# note on the Updates page listing what's waiting.
class Admin::ShippedFileUpdatesNoticeTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  PENDING = [ { kind: :script, name: "gallery.js", installed: "1.0.0", bundled: "1.1" } ].freeze

  def themes_link_dot?
    body = response.body
    i = body.index(%(href="/admin/themes"))
    i && body[i, 400].include?("theme or script update")
  end

  test "with an update waiting: the Themes link has a dot and the Updates page lists it" do
    ShippedFileInspector.stubs(:pending_updates).returns(PENDING)
    get admin_updates_path

    assert_response :success
    assert themes_link_dot?, "dot beside the Themes link"
    assert_match "1 theme or script update available", response.body
    assert_match "site/javascript/gallery.js", response.body
    assert_match "v1.0.0 → v1.1", response.body
  end

  test "with nothing waiting: no dot and no note" do
    ShippedFileInspector.stubs(:pending_updates).returns([])
    get admin_updates_path

    assert_response :success
    assert_not themes_link_dot?
    assert_no_match "theme or script update", response.body
  end
end
