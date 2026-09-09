require "test_helper"

# Saving a settings page with no edits used to rewrite the file, bumping mtime
# with identical bytes. Site Sync tracks size + mtime, so that showed up as
# "Refresh Sync Status" reporting files changed that hadn't been.
class ConfigSaveNoOpTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @path = File.join(SiteConfig::INTEGRATIONS_PATH, "postmark.yml")
    # Snapshot rather than assume — this test writes the real integrations file
    # in the test site, and leaving it behind changes what later tests see.
    @original = File.exist?(@path) ? File.binread(@path) : nil
  end

  teardown do
    if @original
      File.write(@path, @original)
    else
      FileUtils.rm_f(@path)
    end
  end

  test "re-saving Postmark with the same values doesn't touch the file" do
    # Establish a saved state.
    patch admin_newsletters_config_path, params: { test: { server_token: "tok-123" } }
    assert File.exist?(@path), "precondition — the file was written"

    File.utime(Time.at(1_000_000), Time.at(1_000_000), @path)
    before_mtime = File.stat(@path).mtime.to_i
    before_bytes = File.binread(@path)

    # Save again, changing nothing.
    patch admin_newsletters_config_path, params: { test: { server_token: "tok-123" } }

    assert_equal before_bytes, File.binread(@path), "precondition — content unchanged"
    assert_equal before_mtime, File.stat(@path).mtime.to_i,
      "an unchanged save must not bump mtime — Site Sync reads that as an edit"
  end

  test "a real change still writes" do
    patch admin_newsletters_config_path, params: { test: { server_token: "tok-123" } }
    File.utime(Time.at(1_000_000), Time.at(1_000_000), @path)

    patch admin_newsletters_config_path, params: { test: { server_token: "tok-456" } }

    assert_operator File.stat(@path).mtime.to_i, :>, 1_000_000
    assert_match "tok-456", File.read(@path)
  end
end
