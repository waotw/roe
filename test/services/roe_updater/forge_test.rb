require "test_helper"

# The forge host was written into seven places across VersionChecker and
# Downloader. The update path is the one thing that must not break — a user
# whose updater points at a dead host has no way back in — so moving forge
# shouldn't mean editing seven files and hoping none was missed.
class RoeUpdater::ForgeTest < ActiveSupport::TestCase
  setup { @env = ENV.to_h.slice("ROE_FORGE_HOST", "ROE_FORGE_REPO") }

  teardown do
    ENV.delete("ROE_FORGE_HOST")
    ENV.delete("ROE_FORGE_REPO")
    @env.each { |k, v| ENV[k] = v }
  end

  # Nothing changes until something sets otherwise.
  test "defaults to Codeberg, exactly as before" do
    assert_equal "codeberg.org", RoeUpdater::Forge.host
    assert_equal "waotw/roe", RoeUpdater::Forge.repo
    assert_equal "https://codeberg.org/waotw/roe", RoeUpdater::Forge.https_url
    assert_equal "git@codeberg.org:waotw/roe.git", RoeUpdater::Forge.ssh_url
    assert_equal "https://codeberg.org/waotw/roe/releases/tag/v0.3.0",
                 RoeUpdater::Forge.release_page_url("v0.3.0")
    assert_equal "https://codeberg.org/api/v1/repos/waotw/roe/releases/tags/v0.3.0",
                 RoeUpdater::Forge.api_release_url("v0.3.0")
  end

  test "the host and repo can be moved by environment" do
    ENV["ROE_FORGE_HOST"] = "github.com"
    ENV["ROE_FORGE_REPO"] = "waotw/roe"

    assert_equal "https://github.com/waotw/roe", RoeUpdater::Forge.https_url
    assert_equal "git@github.com:waotw/roe.git", RoeUpdater::Forge.ssh_url
  end

  test "a blank override falls back rather than producing a broken URL" do
    ENV["ROE_FORGE_HOST"] = ""

    assert_equal "codeberg.org", RoeUpdater::Forge.host
  end

  # The download host has to be the host the version was found on.
  test "the downloader clones from the configured forge" do
    ENV["ROE_FORGE_HOST"] = "example.org"

    assert_equal "https://example.org/waotw/roe", RoeUpdater::Forge.https_url
  end

  # Anything still naming the old constant resolves to the configured value
  # rather than a second, drifting copy.
  test "the legacy constant still resolves" do
    assert_equal RoeUpdater::Forge::DEFAULT_REPO, RoeUpdater::VersionChecker::CODEBERG_REPO
  end
end
