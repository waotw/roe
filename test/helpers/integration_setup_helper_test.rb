require "test_helper"

class IntegrationSetupHelperTest < ActionView::TestCase
  include IntegrationSetupHelper

  # ── site_deployed? — the authoritative "we shipped" signal ────────────────

  test "site_deployed? is false when no deploy file exists" do
    File.stubs(:exist?).with(PerformDeployJob::LAST_DEPLOY_FILE).returns(false)
    assert_not site_deployed?
  end

  test "site_deployed? is true when the deploy file records a completed_at" do
    stub_deploy_file("completed_at" => Time.current.iso8601)
    assert site_deployed?
  end

  test "site_deployed? is false when the deploy file has no completed_at" do
    stub_deploy_file("target" => "fly")
    assert_not site_deployed?
  end

  test "site_deployed? swallows a malformed deploy file" do
    File.stubs(:exist?).with(PerformDeployJob::LAST_DEPLOY_FILE).returns(true)
    YAML.stubs(:safe_load_file).returns("not a hash")
    assert_not site_deployed?
  end

  # ── the partial's deployed branch renders the live-admin link ─────────────

  test "hidden-setup partial shows the live-admin link when deployed" do
    stub_deploy_file("completed_at" => Time.current.iso8601)
    SiteConfig.stubs(:site_url).returns("https://example.com")
    render partial: "admin/configs/local_setup_hidden"
    assert_select "[data-test=live-admin-link][href=?]", "https://example.com/admin/configs/payments/edit"
    assert_select "[data-test=deploy-settings-link]", count: 0
  end

  test "hidden-setup partial shows deploy links when not deployed" do
    File.stubs(:exist?).with(PerformDeployJob::LAST_DEPLOY_FILE).returns(false)
    render partial: "admin/configs/local_setup_hidden"
    assert_select "[data-test=live-admin-link]", count: 0
    assert_select "[data-test=deploy-settings-link]"
    assert_select "[data-test=deploy-guide-link]"
  end

  private

  def stub_deploy_file(hash)
    File.stubs(:exist?).with(PerformDeployJob::LAST_DEPLOY_FILE).returns(true)
    YAML.stubs(:safe_load_file).returns(hash)
  end
end
