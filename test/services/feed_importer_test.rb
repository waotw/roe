require "test_helper"
require "tmpdir"

# Maps parsed feeds (the same real-world snapshots the parser test uses) into
# Roe draft posts. Writes go to a temp dir — never /site.
class FeedImporterTest < ActiveSupport::TestCase
  FEEDS = Rails.root.join("test", "fixtures", "feeds")

  def feed(name)
    PodcastFeedParser.parse(File.read(FEEDS.join(name)))
  end

  def frontmatter(content)
    YAML.safe_load(content[/\A---\n(.*?)\n---\n/m, 1])
  end

  def body(content)
    content.sub(/\A---\n.*?\n---\n/m, "")
  end

  # --- classification (preview split) --------------------------------------
  test "classify splits audio items from text items" do
    assert_equal({ total: 3, episodes: 3, articles: 0 }, FeedImporter.classify(feed("npr_all_songs.xml")[:items]))
    assert_equal({ total: 3, episodes: 0, articles: 3 }, FeedImporter.classify(feed("verge.xml")[:items]))
    assert_equal({ total: 19, episodes: 0, articles: 19 }, FeedImporter.classify(feed("briefcase_full.xml")[:items]))
    assert_equal({ total: 9, episodes: 9, articles: 9 - 9 }, FeedImporter.classify(feed("briefcase_podcast.xml")[:items]))
  end

  # --- episode mapping ------------------------------------------------------
  test "an episode maps to a draft podcast post with remote audio and carried metadata" do
    item = feed("npr_all_songs.xml")[:items].first
    importer = FeedImporter.new(feed: { items: [] }, kind: :episodes, podcast_key: "myshow")
    _slug, content = importer.content_for(item)
    fm = frontmatter(content)

    assert_equal "podcast", fm["post_type"]
    assert_equal "myshow",  fm["podcast"]
    assert_equal "draft",   fm["status"]
    assert_equal item[:enclosure_url], fm["audio"], "audio referenced remotely"
    assert_kind_of Integer, fm["audio_bytes"]
    assert_equal "audio/mpeg", fm["audio_type"]
    assert_equal item[:guid], fm["guid"], "episodes dedupe on guid"
    assert fm["date"].present? && fm["duration"].present?
    assert body(content).present?, "show notes converted to markdown"
  end

  test "explicit is normalized to true/false and absent when the feed omits it" do
    importer = FeedImporter.new(feed: { items: [] }, kind: :episodes, podcast_key: "s")
    yes = importer.content_for({ title: "a", enclosure_url: "u.mp3", enclosure_type: "audio/mpeg", explicit: "yes" }).last
    no  = importer.content_for({ title: "b", enclosure_url: "u.mp3", enclosure_type: "audio/mpeg", explicit: "clean" }).last
    absent = importer.content_for({ title: "c", enclosure_url: "u.mp3", enclosure_type: "audio/mpeg" }).last

    assert_equal "true",  frontmatter(yes)["explicit"]
    assert_equal "false", frontmatter(no)["explicit"]
    assert_nil frontmatter(absent)["explicit"]
  end

  # --- article mapping ------------------------------------------------------
  test "an article maps to a draft article post with source_url and a converted body" do
    item = feed("verge.xml")[:items].first
    importer = FeedImporter.new(feed: { items: [] }, kind: :articles)
    _slug, content = importer.content_for(item)
    fm = frontmatter(content)

    assert_equal "article", fm["post_type"]
    assert_equal "draft",   fm["status"]
    assert_equal item[:link], fm["source_url"], "articles dedupe on source_url"
    assert_nil fm["audio"], "articles carry no audio"
    assert body(content).present?, "content:encoded converted to markdown"
  end

  # --- full import + dedup --------------------------------------------------
  test "importing episodes writes files, then re-importing skips them by guid" do
    Dir.mktmpdir do |dir|
      run1 = FeedImporter.new(feed: feed("npr_all_songs.xml"), kind: :episodes, podcast_key: "default", posts_dir: dir).import
      assert_equal 3, run1.imported
      assert_equal 0, run1.skipped
      assert_equal 3, Dir.children(dir).count { |f| f.end_with?(".md") }

      run2 = FeedImporter.new(feed: feed("npr_all_songs.xml"), kind: :episodes, podcast_key: "default", posts_dir: dir).import
      assert_equal 0, run2.imported
      assert_equal 3, run2.skipped, "guids already imported are skipped"
    end
  end

  # --- filename collision never overwrites ---------------------------------
  test "a slug collision with an existing file appends -N instead of overwriting" do
    Dir.mktmpdir do |dir|
      existing = File.join(dir, "same-title.md")
      File.write(existing, "---\ntitle: \"pre-existing\"\n---\nkeep me\n")

      one_item = { items: [ { title: "Same Title", link: "https://example.com/x", content_html: "<p>new</p>" } ] }
      result = FeedImporter.new(feed: one_item, kind: :articles, posts_dir: dir).import

      assert_equal [ "same-title-2" ], result.slugs
      assert_equal "keep me\n", File.read(existing).split("---\n").last, "original file untouched"
      assert_equal "same-title-2", frontmatter(File.read(File.join(dir, "same-title-2.md")))["url_name"]
    end
  end

  # --- dedup on guid when links aren't unique (monome) ---------------------
  test "articles with a shared link dedupe on guid, not source_url" do
    Dir.mktmpdir do |dir|
      run1 = FeedImporter.new(feed: feed("monome.xml"), kind: :articles, posts_dir: dir).import
      assert_equal 3, run1.imported, "distinct guids all import despite one shared link"
      assert_equal 3, run1.slugs.uniq.size, "collisions disambiguate to distinct slugs (monome, monome-2, …)"

      run2 = FeedImporter.new(feed: feed("monome.xml"), kind: :articles, posts_dir: dir).import
      assert_equal 0, run2.imported
      assert_equal 3, run2.skipped, "re-import skips by guid, not the shared link"
    end
  end

  # --- guardrails -----------------------------------------------------------
  test "episodes require a podcast_key" do
    assert_raises(ArgumentError) { FeedImporter.new(feed: { items: [] }, kind: :episodes) }
  end
end
