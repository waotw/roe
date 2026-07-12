require "test_helper"

# Proves the "Test nightly" bypass is closed: on a development checkout,
# no update can start — not even with prerelease=true, which used to slip
# past block_on_dev_install.
class Admin::UpdatesDevBlockTest < ActionDispatch::IntegrationTest
  def setup
    sign_in_as(users(:one))
  end

  def with_dev_install(value)
    sc = RoeUpdater::VersionChecker.singleton_class
    sc.send(:alias_method, :__orig_di, :dev_install?)
    sc.send(:define_method, :dev_install?) { value }
    yield
  ensure
    sc.send(:alias_method, :dev_install?, :__orig_di)
    sc.send(:remove_method, :__orig_di)
  end

  test "prerelease=true no longer bypasses the dev-install block" do
    assert_no_difference -> { UpdateStatus.count } do
      with_dev_install(true) do
        post admin_start_update_path, params: { version: "9.9.9-nightly.1", prerelease: "true" }
      end
    end
    assert_redirected_to admin_updates_path
    assert_match(/development checkout/i, flash[:alert])
  end

  test "a regular start is also blocked on a dev checkout" do
    assert_no_difference -> { UpdateStatus.count } do
      with_dev_install(true) do
        post admin_start_update_path, params: { version: "9.9.9" }
      end
    end
    assert_redirected_to admin_updates_path
    assert_match(/development checkout/i, flash[:alert])
  end

  # Stub the network version check so the page renders without hitting git.
  def with_prerelease_available
    vc = RoeUpdater::VersionChecker.singleton_class
    vc.send(:alias_method, :__orig_cfu, :check_for_updates)
    vc.send(:define_method, :check_for_updates) do
      { prerelease_available: true, prerelease_version: "9.9.9-nightly.1", prerelease_url: nil }
    end
    yield
  ensure
    vc.send(:alias_method, :check_for_updates, :__orig_cfu)
    vc.send(:remove_method, :__orig_cfu)
  end

  test "on a dev checkout the pre-release panel shows a git note, not the button" do
    with_dev_install(true) do
      with_prerelease_available do
        get admin_updates_path
      end
    end
    assert_response :success
    assert_match(/switch versions with/i, response.body)  # dev git-note shown
    refute_match(/Test pre-release update/, response.body) # destructive button hidden
  end

  test "a user install (not a dev checkout) is allowed to start an update" do
    # dev_install? false → the guard doesn't block; the action creates the
    # UpdateStatus and enqueues the job (no real update runs in the test
    # queue adapter).
    with_dev_install(false) do
      assert_difference -> { UpdateStatus.count }, 1 do
        post admin_start_update_path, params: { version: "9.9.9" }
      end
    end
    assert_redirected_to admin_updates_path
  end
end
