require "test_helper"

# The forge host was written into seven places across VersionChecker and
# Downloader. The update path is the one thing that must not break — a user
# whose updater points at a dead host has no way back in — so moving forge
# shouldn't mean editing seven files and hoping none was missed.
class RoeUpdater::ForgeTest < ActiveSupport::TestCase
  VARS = %w[ROE_FORGE_HOST ROE_FORGE_REPO ROE_FORGE_URLS].freeze

  setup { @env = ENV.to_h.slice(*VARS) }

  teardown do
    VARS.each { |k| ENV.delete(k) }
    @env.each { |k, v| ENV[k] = v }
  end

  # An install knows only what was compiled into it. One place to look means
  # stranded the day that place goes away — and it can't be rescued by an
  # update, because updating is the broken thing.
  test "there is always more than one place to look" do
    assert_operator RoeUpdater::Forge.mirrors.length, :>, 1,
      "a single mirror is a single point of failure with no way back in"
  end

  # go-roe.com can be repointed without shipping a release, so it goes first.
  test "the preferred mirror is the one that can be moved without a release" do
    assert_equal "https://go-roe.com/roe.git", RoeUpdater::Forge.mirrors.first
    assert_equal RoeUpdater::Forge.mirrors.first, RoeUpdater::Forge.https_url
  end

  # A redirect can't be its own fallback: when go-roe.com is down, the client
  # can't ask go-roe.com where else to go.
  test "the fallbacks are direct forges, not more indirection" do
    fallbacks = RoeUpdater::Forge.mirrors.drop(1)

    assert fallbacks.any?, "nothing to fall back to"
    fallbacks.each do |url|
      assert_not_equal "go-roe.com", URI.parse(url).host,
        "#{url} routes through the thing it's meant to cover for"
    end
  end

  # Where Roe lives now. Codeberg and Sourcehut both bar AI-assisted projects.
  test "GitHub is in the list" do
    assert_includes RoeUpdater::Forge.mirrors, "https://github.com/waotw/roe"
  end

  # Dropping it is what would strand an install that predates the move — it
  # still points at Codeberg and can only be repointed by an update it can't
  # fetch from anywhere else.
  test "Codeberg stays reachable for installs that predate the move" do
    assert_includes RoeUpdater::Forge.mirrors, "https://codeberg.org/waotw/roe"
  end

  test "the ssh fallback follows the move" do
    assert_equal "github.com", RoeUpdater::Forge.host
    assert_equal "waotw/roe", RoeUpdater::Forge.repo
    assert_equal "git@github.com:waotw/roe.git", RoeUpdater::Forge.ssh_url
  end

  # go-roe.com redirects the git path only, so a release page or API call aimed
  # at it 404s rather than failing over.
  test "human links and API calls skip the redirect and name a real forge" do
    assert_equal "https://github.com/waotw/roe/releases/tag/v0.3.0",
                 RoeUpdater::Forge.release_page_url("v0.3.0")
    assert_nil RoeUpdater::Forge.api_release_url("v0.3.0", "https://go-roe.com/roe.git")
    assert_not_includes RoeUpdater::Forge.api_release_urls("v0.3.0").join(" "), "go-roe.com"
  end

  # Release notes were the only forge-specific call, and GitHub answers on a
  # different host entirely — so swapping `host` could never have expressed it.
  test "release metadata follows each forge's own API shape" do
    assert_equal "https://codeberg.org/api/v1/repos/waotw/roe/releases/tags/v0.3.0",
                 RoeUpdater::Forge.api_release_url("v0.3.0", "https://codeberg.org/waotw/roe")
    assert_equal "https://api.github.com/repos/waotw/roe/releases/tags/v0.3.0",
                 RoeUpdater::Forge.api_release_url("v0.3.0", "https://github.com/waotw/roe")
  end

  test "the mirror list can be replaced outright" do
    ENV["ROE_FORGE_URLS"] = "https://one.example/roe, https://two.example/roe"

    assert_equal [ "https://one.example/roe", "https://two.example/roe" ],
                 RoeUpdater::Forge.mirrors
  end

  # Someone who pinned a host meant that host. Falling through to ours would
  # quietly ignore them and update from somewhere they didn't choose.
  test "a pinned host replaces the list rather than joining it" do
    ENV["ROE_FORGE_HOST"] = "git.example.org"

    assert_equal [ "https://git.example.org/waotw/roe" ], RoeUpdater::Forge.mirrors
  end

  test "the host and repo can be moved by environment" do
    ENV["ROE_FORGE_HOST"] = "github.com"
    ENV["ROE_FORGE_REPO"] = "waotw/roe"

    assert_equal "https://github.com/waotw/roe", RoeUpdater::Forge.https_url
    assert_equal "git@github.com:waotw/roe.git", RoeUpdater::Forge.ssh_url
  end

  test "a blank override falls back rather than producing a broken URL" do
    ENV["ROE_FORGE_HOST"] = ""

    assert_equal "github.com", RoeUpdater::Forge.host
  end

  # The download list has to be the list the version was found on.
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
