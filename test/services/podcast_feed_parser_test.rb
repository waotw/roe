require "test_helper"

# Parses real-world feed snapshots (test/fixtures/feeds/) offline, plus a small
# synthetic feed for exact field assertions. The fixtures cover the four shapes
# the FeedImporter has to survive:
#   npr_all_songs.xml    — standard RSS 2.0 + iTunes podcast (episodes)
#   verge.xml            — large RSS blog with content:encoded (articles)
#   briefcase_full.xml   — Atom blog feed, body in <content> (articles)
#   briefcase_podcast.xml— FeedPress hybrid Atom: bare <link rel=enclosure> mp3s
class PodcastFeedParserTest < ActiveSupport::TestCase
  FEEDS = Rails.root.join("test", "fixtures", "feeds")

  def parse(name)
    PodcastFeedParser.parse(File.read(FEEDS.join(name)))
  end

  # --- NPR All Songs Considered: RSS podcast -------------------------------
  test "RSS podcast: every item is an episode with audio, an integer length, and a body" do
    items = parse("npr_all_songs.xml")[:items]
    assert_operator items.size, :>=, 1

    items.each do |i|
      assert i[:enclosure_url].present?, "expected an audio enclosure"
      assert i[:enclosure_type].to_s.start_with?("audio"), "expected an audio type"
      assert i[:title].present?
      assert (i[:content_html] || i[:description]).present?, "expected a body"
    end

    ep = items.first
    assert_kind_of Integer, ep[:enclosure_length], "length must be cast to an Integer"
    assert ep[:duration].present?
  end

  # --- The Verge: large RSS blog (articles) --------------------------------
  test "RSS blog: items are articles — no audio, a content:encoded body, and a link to dedupe on" do
    items = parse("verge.xml")[:items]
    assert_operator items.size, :>=, 1

    items.each do |i|
      assert i[:enclosure_url].blank?, "an article should not carry audio"
      assert i[:content_html].present?, "expected the content:encoded body"
      assert i[:link].present?, "articles dedupe on link (source_url)"
    end
  end

  # --- The Briefcase full feed: Atom blog (articles) -----------------------
  test "Atom blog: articles with a body via <content>/description and no audio" do
    items = parse("briefcase_full.xml")[:items]
    assert_operator items.size, :>=, 1

    items.each do |i|
      assert i[:enclosure_url].blank?
      assert (i[:content_html] || i[:description]).present?, "expected a body"
    end
  end

  # --- The Briefcase podcast: FeedPress hybrid Atom (episodes) --------------
  test "FeedPress hybrid Atom: bare mp3 enclosures classify as audio and iTunes author is read" do
    parsed = parse("briefcase_podcast.xml")
    items = parsed[:items]
    assert_operator items.size, :>=, 1

    ep = items.first
    assert ep[:enclosure_url].to_s.end_with?(".mp3"), "expected the mp3 enclosure href"
    assert_equal "audio/mpeg", ep[:enclosure_type], "MIME inferred from .mp3 when the feed omits type"
    assert ep[:author].present?, "itunes:author (bare <author>) should be read"
    assert (ep[:content_html] || ep[:description]).present?, "expected show notes"
    assert_equal "Benjamin Welch", parsed[:channel][:author]
  end

  # --- monome: RSS blog that reuses one title + link for every item --------
  test "RSS blog reusing one title/link per item: guids stay unique, bodies present" do
    items = parse("monome.xml")[:items]
    assert_operator items.size, :>=, 2

    assert_equal [ "monome" ], items.map { |i| i[:title] }.uniq, "feed reuses one title"
    assert_equal 1, items.map { |i| i[:link] }.uniq.size, "feed reuses one link"
    assert_equal items.size, items.map { |i| i[:guid] }.uniq.size, "guids are the only unique id"

    items.each do |i|
      assert i[:enclosure_url].blank?, "articles, not episodes"
      assert i[:description].present?, "body comes from description"
    end
  end

  # --- Exact field mapping (synthetic, precise) ----------------------------
  test "reads content:encoded, itunes episode/season/type, and casts length to Integer" do
    xml = <<~XML
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
           xmlns:content="http://purl.org/rss/1.0/modules/content/">
        <channel><title>Show</title>
          <item>
            <title>Ep 5</title><guid>g5</guid>
            <description>short summary</description>
            <content:encoded><![CDATA[<p>full <strong>body</strong></p>]]></content:encoded>
            <itunes:episode>5</itunes:episode>
            <itunes:season>2</itunes:season>
            <itunes:episodeType>full</itunes:episodeType>
            <itunes:duration>1830</itunes:duration>
            <enclosure url="https://cdn.example.com/e5.mp3" type="audio/mpeg" length="48200000"/>
          </item>
        </channel>
      </rss>
    XML
    i = PodcastFeedParser.parse(xml)[:items].first

    assert_equal "<p>full <strong>body</strong></p>", i[:content_html]
    assert_equal "5", i[:episode]
    assert_equal "2", i[:season]
    assert_equal "full", i[:episode_type]
    assert_equal 48_200_000, i[:enclosure_length]
    assert_kind_of Integer, i[:enclosure_length]
    assert_equal "audio/mpeg", i[:enclosure_type]
  end

  # --- MIME inference edge (bare enclosure, no type) -----------------------
  test "infers audio MIME from the URL extension when the enclosure has no type" do
    xml = <<~XML
      <feed xmlns="http://www.w3.org/2005/Atom">
        <entry><id>x</id><title>Bare</title>
          <link rel="enclosure" href="https://s3.example.com/a/ep.mp3?sig=abc"/>
        </entry>
      </feed>
    XML
    i = PodcastFeedParser.parse(xml)[:items].first
    assert_equal "https://s3.example.com/a/ep.mp3?sig=abc", i[:enclosure_url]
    assert_equal "audio/mpeg", i[:enclosure_type], "query string must not defeat extension sniffing"
  end
end
