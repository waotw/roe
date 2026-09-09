# frozen_string_literal: true

require "test_helper"

# What the failed-deploy panel offers you.
#
# It used to offer one way forward: clear the build cache and re-deploy. But
# most failures are fixed outside Roe and then simply re-run — you started
# Docker, added the registry token, waited for DNS — and none of those need a
# cold build. Making the expensive path the only path cost minutes every time.
class Admin::DeployFailurePanelTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  teardown { Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY) }

  # Scoped to the failure panel deliberately: admin_start_deploy_path also
  # appears further down the page as the normal Deploy button's data-deploy-url,
  # so an unscoped assert_match would pass whether or not the retry button
  # exists at all.
  # Everything from the panel's heading up to the page's own Deploy button,
  # which is rendered well below it (index.html.erb:23 vs :509).
  def panel
    body = response.body
    start = body.index("Deploy failed")
    return "" unless start

    body[start...(body.index("data-deploy-url", start) || body.length)]
  end

  def failed_deploy(log: "something went wrong", error: nil, failures: 1)
    Rails.cache.write(
      PerformDeployJob::STATUS_CACHE_KEY,
      { state: :failed, target: "kamal", version_tag: "1", log: log, error: error,
        consecutive_failures: failures },
      expires_in: 1.hour
    )
  end

  test "a failed deploy offers a plain retry" do
    failed_deploy
    get admin_updates_path

    assert_response :success
    assert_match "Retry deploy", panel
    assert_match admin_start_deploy_path, panel,
      "the cheap path back has to be there"
  end

  test "dismissing is always available" do
    failed_deploy
    get admin_updates_path

    assert_match admin_dismiss_deploy_path, panel
  end

  # ── The cold build only appears when there's a reason ─────────────────────

  test "a first, ordinary failure doesn't offer a cold build" do
    failed_deploy(log: "some unremarkable build error", failures: 1)
    get admin_updates_path

    assert_no_match admin_reset_and_retry_deploy_path, panel,
      "several minutes offered for no stated reason"
  end

  # Our pattern list will never be complete, so the count is what catches
  # everything it misses. Without it, an unrecognised cache failure would
  # leave someone retrying a warm build forever with no way out.
  test "a second failure in a row offers it, whatever the error was" do
    failed_deploy(log: "some unremarkable build error", failures: 2)
    get admin_updates_path

    assert_match admin_reset_and_retry_deploy_path, panel
  end

  test "a cache-shaped error offers it on the first failure" do
    failed_deploy(log: "ERROR: failed to compute cache key: not found", failures: 1)
    get admin_updates_path

    assert_match admin_reset_and_retry_deploy_path, panel
  end

  # Docker being off is diagnosable and is definitely not a cache problem.
  test "a diagnosed non-cache failure still doesn't offer it" do
    failed_deploy(log: "Cannot connect to the Docker daemon", failures: 1)
    get admin_updates_path

    assert_no_match admin_reset_and_retry_deploy_path, panel
  end

  test "when offered, the cold build leads and the plain retry steps back" do
    failed_deploy(log: "failed to compute cache key", failures: 1)
    get admin_updates_path

    # The class attribute sits before the label in the markup, so slice by
    # form rather than forward from the text.
    forms = panel.split("<form").map { |f| "<form#{f}" }
    plain = forms.find { |f| f.include?("Retry deploy") }
    cold  = forms.find { |f| f.include?("Retry without cache") }

    assert cold.present?, "the cold build should be shown here"
    assert_match(/bg-blue-100/, cold, "the cold build should lead")
    assert_match(/bg-white/, plain, "the plain retry should be the quiet one now")
  end

  # The cold build costs minutes, so it says so before running.
  test "only the cache-clearing retry asks for confirmation" do
    failed_deploy(log: "failed to compute cache key", failures: 1)
    get admin_updates_path

    buttons = panel[/Retry deploy.*?Dismiss/m]

    assert_match(/takes several extra minutes/, buttons)
    assert_equal 1, buttons.scan(/turbo-confirm|turbo_confirm/).size,
      "a plain retry shouldn't need confirming"
  end

  test "a recognised failure is explained above the log" do
    failed_deploy(log: "Cannot connect to the Docker daemon at unix:///var/run/docker.sock")
    get admin_updates_path

    # The apostrophe arrives HTML-escaped, so match around it rather than
    # pinning the entity.
    assert_match(/Docker isn(&#39;|&rsquo;|')t running on this computer/, response.body)
    assert_match "Docker Desktop", response.body
  end

  test "an unrecognised failure still shows the log and the buttons" do
    failed_deploy(log: "totally novel explosion")
    get admin_updates_path

    assert_match "totally novel explosion", panel
    assert_match "Retry deploy", panel
  end
end
