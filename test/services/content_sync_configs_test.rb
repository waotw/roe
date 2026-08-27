# frozen_string_literal: true

require "test_helper"

# Files are the source of truth; the SiteConfig rows are a projection of them.
#
# ContentSync used to rebuild only site.yml and the defaults, so after a sync
# brought in new feature configs the database still served the pre-sync values
# — the files said one thing and the running site did another until a restart.
class ContentSyncConfigsTest < ActiveSupport::TestCase
  def store_path = SiteConfig::FEATURES_PATH.join("store.yml")

  # Bootsnap caches YAML.load_file keyed on size + mtime, so rewriting a file
  # to the same byte length inside the same second serves the previous parse
  # and the test measures the cache instead of the code. Stamping the mtime
  # forward is what a real transfer does anyway — rsync carries the source's
  # mtime across, which is why this doesn't bite in production.
  def write_store(currency)
    FileUtils.mkdir_p(File.dirname(store_path))
    existing = File.exist?(store_path) ? File.mtime(store_path) : Time.now
    File.write(store_path, "currency: #{currency}\nproduct_categories: []\n")
    # Strictly forward of the previous mtime — `Time.now + n` twice in the same
    # second gives the same stamp, so the cache key wouldn't change.
    t = existing + 10
    File.utime(t, t, store_path)
  end

  teardown do
    File.delete(store_path) if File.exist?(store_path)
    SiteConfig.reload!
  end

  test "a feature config changed on disk reaches the database" do
    write_store("usd")
    SiteConfig.sync_from_file("features/store")
    assert_equal "usd", SiteConfig.feature("store", "currency"), "precondition"

    # What rsync does: replaces the file underneath a running app.
    write_store("gbp")
    SiteConfig.reload!("features/store")

    ContentSync.new.send(:sync_configs)

    assert_equal "gbp", SiteConfig.feature("store", "currency"),
      "the database is still serving the pre-sync config"
  end

  test "every config file on disk is covered" do
    write_store("usd")
    types = SiteConfig.db_backed_types

    assert_includes types, "features/store"
    assert_includes types, "site"
    Dir.glob(SiteConfig::FEATURES_PATH.join("*.yml")).each do |f|
      assert_includes types, "features/#{File.basename(f, '.yml')}"
    end
  end

  # The list reload! iterated was maintained by hand and had already fallen
  # behind — features/music was added and never added to it.
  # Creates only what it needs, and removes exactly what it created. Writing a
  # stub podcast.yml into the shared test site and leaving it behind broke
  # unrelated tests that iterate PodcastConfig entries — the shared site is
  # everyone's, so a test has to leave it as it found it.
  test "reloading everything covers every feature, not a hand-kept list" do
    path = SiteConfig::FEATURES_PATH.join("music.yml")
    existed = File.exist?(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "audience: free\n") unless existed

    assert_includes SiteConfig.db_backed_types, "features/music"
  ensure
    File.delete(path) if path && !existed && File.exist?(path)
  end

  # Configs first: Product's after_save writes to store.yml, and it has to be
  # judging against the config the sync just brought in.
  test "configs are rebuilt before content syncs" do
    source = File.read(Rails.root.join("app", "services", "content_sync.rb"))
    body = source[/def sync_all.*?^  end/m]
    order = %w[sync_configs sync_products].map { |m| body.index(m) }

    assert order.all?, "sync_all no longer has both steps"
    assert order[0] < order[1], "products sync before the configs they depend on"
  end
end
