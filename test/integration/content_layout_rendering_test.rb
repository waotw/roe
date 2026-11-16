require "test_helper"

# A content type's layout draws its page: Roe's default reproduces the old
# post-type templates, a site's own copy changes the order, and a part the
# body already has isn't drawn twice.
class ContentLayoutRenderingTest < ActionDispatch::IntegrationTest
  # These tests are about what a site's own layouts do, so content layouts
  # are on; the off state has its own tests.
  setup { SiteConfig.stubs(:content_layouts?).returns(true) }

  CARD = "```card\ntype: player\n```".freeze

  teardown do
    Dir.glob(File.join(ContentLayout::SITE_DIR, "*#{ContentLayout::EXT}")).each { |f| FileUtils.rm_f(f) }
  end

  def a_post(type = "article", content: "Words.", **fields)
    @n = (@n || 0) + 1
    create(:post,
      metadata: { "title" => "#{type.capitalize} post #{@n}", "status" => "published", "date" => "2024-03-05",
                  "audience" => "everyone", "post_type" => type }.merge(fields.transform_keys(&:to_s)),
      content: content)
  end

  def a_product(content: "About it.", **fields)
    @n = (@n || 0) + 1
    Product.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "products", "thing-#{@n}.md"),
      content: content,
      metadata: { "title" => "Thing #{@n}", "url_name" => "thing-#{@n}", "status" => "published",
                  "sku" => "THING-#{@n}", "price" => 12.0 }.merge(fields.transform_keys(&:to_s)))
  end

  def site_layout(name, text)
    FileUtils.mkdir_p(ContentLayout::SITE_DIR)
    path = ContentLayout.site_path(name)
    File.write(path, text)
    File.utime(Time.now + rand(1..1000), Time.now + rand(1..1000), path)
  end

  # Class names in page order, for the parts we care about.
  def order(*selectors)
    doc = Nokogiri::HTML(response.body)
    doc.css(selectors.join(", ")).map { |n| (n["class"].split & selectors.map { |s| s.delete(".") }).first }
  end

  # ── Roe's defaults ──

  test "an article keeps the old header: title and RSS, subtitle, date and author, then the body" do
    post = a_post(subtitle: "A subtitle", author: "Ben")
    get post_path(post.url_name)

    assert_select "article.post.post-article > .content > header.post-header" do
      assert_select ".post-header-top h1.post-title", post.title
      assert_select ".post-header-top a.feed-link[href='/feed.xml']"
      assert_select "p.post-subtitle", "A subtitle"
      assert_select ".post-meta time.post-date", /March 05, 2024/
      assert_select ".post-meta .post-author", /Ben/
    end
    assert_select "header.post-header + .post-content", /Words/
  end

  test "parts with nothing to show draw nothing" do
    get post_path(a_post.url_name)
    assert_select ".post-subtitle", 0
    assert_select ".post-author", 0
  end

  test "an audio post's player sits between the header and the body" do
    get post_path(a_post("audio", audio: "/media/audio/a.mp3").url_name)
    assert_equal %w[post-header post-player post-content], order(".post-header", ".post-player", ".post-content")
  end

  test "a podcast episode has its player, body and playlist inside .podcast-episode" do
    first = a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01")
    a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01")

    get post_path(first.url_name)
    assert_select ".podcast-episode .post-player .card-player"
    assert_select ".podcast-episode .post-content"
    # On a post the playlist starts folded: the post is about its episode.
    assert_select ".podcast-episode .collection.playlist details.player-playlist:not([open]) [data-playlist] li", 2
    assert_select "[data-playlist] li.is-current[aria-current=true]", 1
  end

  # ── a site's own layout ──

  test "the site's layout changes the order" do
    site_layout("article", "[body]\n[title]\n")
    post = a_post
    get post_path(post.url_name)
    assert_equal %w[post-content post-title], order(".post-content", ".post-title")
  end

  test "a site's layout without a header part has no post-header" do
    site_layout("article", "[body]\n")
    get post_path(a_post.url_name)
    assert_select "header.post-header", 0
    assert_select ".post-title", 0
  end

  test "a row of boxes without a name gets one layout-row div" do
    site_layout("article", "[subtitle] [date]\n[body]\n")
    get post_path(a_post(subtitle: "Sub").url_name)
    assert_select "div.layout-row > .post-subtitle + .post-date"
  end

  test "the first block is the header, the last the footer, any between are groups" do
    site_layout("article", "[title]\n\nmeta wide:\n[date]\n\n[body]\n\n[subtitle]\n\n[author]\n")
    get post_path(a_post(subtitle: "Sub", author: "Ben").url_name)
    assert_select ".content > header > .post-title"
    assert_select ".content > div.meta.wide > .post-date"
    assert_select ".content > .post-content"
    assert_select ".content > div.layout-group > .post-subtitle"
    assert_select ".content > footer > .post-author"
  end

  test "names give a block and a row their classes" do
    site_layout("article", "top:\nbyline: [date] [author]\n\n[body]\n")
    get post_path(a_post(author: "Ben").url_name)
    assert_select "header.top > div.byline > .post-date + .post-author"
  end

  test "boxes grouped with the body sit inside the content, before or after the writing" do
    site_layout("article", "story:\n[subtitle]\n[body]\n[date]\n")
    get post_path(a_post(subtitle: "Sub").url_name)
    assert_select "div.story > .post-subtitle + .post-content + .post-date"
    assert_select "article header", 0
  end

  test "an empty header is left out" do
    site_layout("article", "[location]\n\n[body]\n")
    get post_path(a_post.url_name)
    assert_select "article header", 0
  end

  test "[excerpt] and [tags] are parts with their own markup" do
    site_layout("article", "[excerpt]\n[tags]\n[body]\n")
    get post_path(a_post(excerpt: "In short.", tags: "arts, culture").url_name)
    assert_select "p.post-excerpt", "In short."
    assert_select "ul.post-tags > li.post-tag", 2
    assert_select "ul.post-tags > li.post-tag", "arts"
  end

  test "each tag opens the site search filtered to it" do
    site_layout("article", "[tags]\n[body]\n")
    get post_path(a_post(tags: "arts, culture").url_name)
    link = css_select("li.post-tag a.post-tag-link[data-controller=search-trigger]").first
    assert_equal "arts", link.text
    assert_equal({ "tagsInclude" => [ "arts" ] }, JSON.parse(link["data-search-trigger-scope-value"]))
  end

  test "a metadata field without a part of its own shows its value" do
    site_layout("article", "[location]\n[body]\n")
    get post_path(a_post(location: "Chicago").url_name)
    assert_select "p.post-field.post-field-location", "Chicago"
  end

  test "layout: in the metadata picks another layout" do
    site_layout("announcement", "[body]\n")
    get post_path(a_post(layout: "announcement").url_name)
    assert_select ".post-title", 0
    assert_select ".post-content", /Words/
  end

  test "Jekyll's layout: page on an imported post keeps the post's header" do
    get post_path(a_post(layout: "page").url_name)
    assert_select "h1.post-title"
  end

  # ── body wins ──

  test "a player card in the body replaces the layout's player" do
    get post_path(a_post("audio", audio: "/media/audio/a.mp3", content: "#{CARD}\n\nWords.").url_name)
    assert_select ".card-player", 1
    assert_select ".post-player", 0
    assert_select ".post-content .card-player"
  end

  test "a page shows only its body by default" do
    page = create(:page, metadata: { "title" => "About", "url_name" => "about-us", "status" => "published" }, content: "# About\n\nHello.")
    get "/#{page.url_name}"
    assert_select "article.page > .content h1", "About"
    assert_select "h1", 1
  end

  # .content wraps the whole layout on every type, so Markdown styles reach the
  # boxes too; the writing alone has its own class.
  test "a page's and a doc's .content wraps the whole layout, with the body named inside it" do
    site_layout("page", "[title]\n[body]\n")
    page = create(:page, metadata: { "title" => "Wrapped", "url_name" => "wrapped", "status" => "published" }, content: "Hello.")
    get "/#{page.url_name}"
    assert_select "article.page > .content > h1.page-title", "Wrapped"
    assert_select "article.page > .content > .page-content", /Hello/
    assert_select ".content .content", 0

    Documentation.stubs(:roe_docs_published?).returns(true)
    get "/documentation/roe/troubleshoot-deployment"
    assert_response :success
    assert_select "article.documentation-page > .content.documentation > .documentation-content"
    assert_select ".content .content", 0
  end

  test "a page connected to a podcast uses the podcast-page layout" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    PodcastConfig.stubs(:get).returns({ "title" => "The Show" })
    page = create(:page, metadata: { "title" => "Show", "url_name" => "the-show", "status" => "published", "podcast" => "show" }, content: "About the show.")

    assert_equal "podcast-page", ContentLayout.for(page).name
    get "/#{page.url_name}"
    assert_select "h1.podcast-page-title", "The Show"
  end

  test "a site's custom page layout doesn't change podcast pages" do
    site_layout("page", "[title]\n[body]\n")
    page = create(:page, metadata: { "title" => "Show", "url_name" => "show-2", "status" => "published", "podcast" => "show" }, content: "x")
    assert_equal "podcast-page", ContentLayout.for(page).name
    assert_equal "page", ContentLayout.for(create(:page, metadata: { "title" => "A", "url_name" => "a-page", "status" => "published" }, content: "x")).name
  end

  test "a page connected to a release uses the music-page layout" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    ReleaseConfig.stubs(:get).returns({ "title" => "Summer EP" })
    ReleaseConfig.stubs(:feed_enabled?).returns(true)
    ReleaseFeed.any_instance.stubs(:paid?).returns(false)
    page = create(:page, metadata: { "title" => "EP", "url_name" => "summer-ep", "status" => "published", "release" => "summer-ep" }, content: "About the record.")

    assert_equal "music-page", ContentLayout.for(page).name
    get "/#{page.url_name}"
    assert_select "h1.release-page-title", "Summer EP"
    assert_select ".release-subscribe a.feed-link[href=?]", "/music/summer-ep.xml"
    assert_select ".content", /About the record/
  end

  test "a release without a feed shows its title and no subscribe links" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    ReleaseConfig.stubs(:get).returns({ "title" => "Singles" })
    ReleaseConfig.stubs(:feed_enabled?).returns(false)
    page = create(:page, metadata: { "title" => "Singles", "url_name" => "singles-page", "status" => "published", "release" => "singles" }, content: "x")

    get "/#{page.url_name}"
    assert_select "h1.release-page-title", "Singles"
    assert_select ".release-subscribe", 0
  end

  # ── release and podcast boxes ──

  test "a music-page shows its release's cover, title, artist, date and tracks" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    ReleaseConfig.stubs(:get).returns({ "title" => "Summer EP", "artist" => "The Band", "release_date" => "2026-11-09",
                                        "cover" => "/media/images/ep.jpg" })
    ReleaseConfig.stubs(:feed_enabled?).returns(false)
    a_post("music", audio: "/media/audio/a.mp3", release: "summer-ep", track_number: 1)
    a_post("music", audio: "/media/audio/b.mp3", release: "summer-ep", track_number: 2)
    page = create(:page, metadata: { "title" => "EP", "url_name" => "ep-page", "status" => "published", "release" => "summer-ep" }, content: "Notes.")

    get "/#{page.url_name}"
    assert_select "img.page-image.page-cover"
    assert_select "h1.release-page-title", "Summer EP"
    assert_select "span.page-author.page-artist", "The Band"
    assert_select "time.page-date.page-release-date[datetime='2026-11-09']", "November 09, 2026"
    # The default pairs [player] and [playlist], above the writing; on a page
    # the list starts open.
    assert_select ".post-player + .collection.playlist details.player-playlist[open] .player-track", 2
    assert_select ".card-player .player-playlist", 0, "the player and the list are separate"
    html = response.body
    assert_operator html.index("collection playlist"), :<, html.index("Notes."), "the audio comes before the writing"
  end

  test "[playlist] without [player] is only the list, as the collection is" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    ReleaseConfig.stubs(:get).returns({ "title" => "Summer EP" })
    ReleaseConfig.stubs(:feed_enabled?).returns(false)
    site_layout("music-page", "[playlist]\n[body]\n")
    a_post("music", audio: "/media/audio/a.mp3", release: "summer-ep", track_number: 1)
    a_post("music", audio: "/media/audio/b.mp3", release: "summer-ep", track_number: 2)
    page = create(:page, metadata: { "title" => "EP", "url_name" => "ep-two", "status" => "published", "release" => "summer-ep" }, content: "Notes.")

    get "/#{page.url_name}"
    assert_select ".card-player", 0
    assert_select ".collection.playlist .player-track", 2
  end

  test "a page with a player card in its body doesn't get a second one from [playlist]" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    ReleaseConfig.stubs(:get).returns({ "title" => "Summer EP" })
    ReleaseConfig.stubs(:feed_enabled?).returns(false)
    a_post("music", audio: "/media/audio/a.mp3", release: "summer-ep", track_number: 1)
    a_post("music", audio: "/media/audio/b.mp3", release: "summer-ep", track_number: 2)
    page = create(:page, metadata: { "title" => "EP", "url_name" => "ep-three", "status" => "published", "release" => "summer-ep" },
                         content: "#{CARD}\n\nNotes.")

    get "/#{page.url_name}"
    assert_select ".card-player[data-player=audio]", 1
    assert_select ".collection.playlist .player-track", 2
  end

  test "[artist] is the track's own, then the release's, then the site's music artist" do
    SiteFeature.stubs(:music_enabled?).returns(true)
    ReleaseConfig.stubs(:get).returns({ "title" => "EP", "artist" => "Release Band" })
    own = a_post("music", audio: "/media/audio/a.mp3", release: "ep", artist: "Guest Singer")
    get post_path(own.url_name)
    assert_select ".post-meta span.post-author.post-artist", /Guest Singer/

    from_release = a_post("music", audio: "/media/audio/b.mp3", release: "ep")
    get post_path(from_release.url_name)
    assert_select "span.post-artist", /Release Band/

    ReleaseConfig.stubs(:get).returns({ "title" => "EP" })
    ReleaseConfig.stubs(:global_artist).returns("Site Artist")
    get post_path(from_release.url_name)
    assert_select "span.post-artist", /Site Artist/
  end

  test "[author] still shows the post's own author on a music layout" do
    site_layout("music", "post-meta: [date] [author] [artist]\n[body]\n")
    ReleaseConfig.stubs(:get).returns({ "artist" => "The Band" })
    post = a_post("music", audio: "/media/audio/a.mp3", release: "ep", author: "Ben")
    get post_path(post.url_name)
    assert_select "span.post-author:not(.post-artist)", /Ben/
    assert_select "span.post-artist", /The Band/
  end

  test "a podcast-page shows its show's artwork, creator, description and link" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    PodcastConfig.stubs(:get).returns({ "title" => "The Show", "author" => "Ben", "artwork" => "show.jpg",
                                        "description" => "A show.", "link" => "https://example.com/" })
    site_layout("podcast-page", "[artwork]\n[podcast title]\n[creator]\n[description]\n[podcast link]\n[body]\n")
    page = create(:page, metadata: { "title" => "Show", "url_name" => "show-page", "status" => "published", "podcast" => "show" }, content: "x")

    get "/#{page.url_name}"
    assert_select "img.page-image.page-artwork[src*='/system/images/show.jpg']"
    assert_select "span.page-author.page-creator", "Ben"
    assert_select "p.page-excerpt.page-description", "A show."
    assert_select "p.page-field.page-field-podcast-link a[href='https://example.com/']", "example.com"
  end

  test "release and podcast boxes draw nothing on a page connected to neither" do
    site_layout("page", "[cover]\n[artist]\n[creator]\n[release date]\n[genre]\n[body]\n")
    page = create(:page, metadata: { "title" => "About", "url_name" => "about-plain", "status" => "published" }, content: "Hello.")
    get "/#{page.url_name}"
    assert_select ".page-cover, .page-artist, .page-creator, .page-release-date, .page-genre", 0
  end

  test "a podcast link that isn't a web address isn't linked" do
    SiteFeature.stubs(:podcast_enabled?).returns(true)
    PodcastConfig.stubs(:get).returns({ "title" => "The Show", "link" => "javascript:alert(1)" })
    site_layout("podcast-page", "[podcast link]\n[body]\n")
    page = create(:page, metadata: { "title" => "Show", "url_name" => "show-js", "status" => "published", "podcast" => "show" }, content: "x")
    get "/#{page.url_name}"
    assert_select ".page-field-podcast-link", 0
  end

  test "a product shows its title, image and button from the layout" do
    product = a_product
    get product_path(product.url_name)
    assert_select ".product .content .product-top h1.product-title", product.title
    assert_select ".product-top .product-price", "$12.00"
  end

  test "a product's own button replaces the layout's; a heading and image in the body show as well" do
    product = a_product(image: "/media/images/x.jpg",
      content: "![Thing](/media/images/x.jpg)\n\n# My heading\n\n```button\nsku: THING-X\n```\n\nAbout it.")
    get product_path(product.url_name)
    assert_equal [ product.title, "My heading" ], css_select("h1.product-title").map { |h| h.text.strip }
    assert_select ".product-top img[src='/media/images/x.jpg']", 1
    assert_select "img[src='/media/images/x.jpg']", 2
    assert_select ".product-top .product-price", 0, "the body's button stands in for the layout's"
  end

  test "an example button inside a four-backtick fence doesn't count" do
    product = a_product(content: "````\n```button\nsku: X\n```\n````\n")
    get product_path(product.url_name)
    assert_select "h1.product-title", product.title
  end

  # ── ⏮ ⏭ in the body's player card ──

  test "a podcast episode's own player card links the episodes before and after it" do
    older  = a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01")
    middle = a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01", content: CARD)
    newer  = a_post("podcast", audio: "/media/audio/3.mp3", podcast: "show", date: "2024-03-01")

    get post_path(middle.url_name)
    assert_select ".post-content .card-player nav.player-series" do
      assert_select "a.player-series-prev[href=?]", "/posts/#{older.url_name}", text: /#{older.title}/
      assert_select "a.player-series-next[href=?]", "/posts/#{newer.url_name}", text: /#{newer.title}/
    end
  end

  test "the first episode has only a next link, and a show of one has none" do
    first = a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01", content: CARD)
    a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01")
    alone = a_post("podcast", audio: "/media/audio/9.mp3", podcast: "solo", date: "2024-01-01", content: CARD)

    get post_path(first.url_name)
    assert_select ".player-series-prev", 0
    assert_select ".player-series-next", 1

    get post_path(alone.url_name)
    assert_select ".player-series", 0
  end

  test "a music track links the tracks before and after it by track number" do
    t2 = a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2, content: CARD)
    t1 = a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1)
    t3 = a_post("music", audio: "/media/audio/c.mp3", release: "ep", track_number: 3)

    get post_path(t2.url_name)
    assert_select "a.player-series-prev[href=?]", "/posts/#{t1.url_name}"
    assert_select "a.player-series-next[href=?]", "/posts/#{t3.url_name}"
  end

  test "audio posts, and a card playing another file, get no links" do
    a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01")
    other = a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01",
      content: "```card\ntype: player\naudio: /media/audio/song.mp3\n```")
    get post_path(other.url_name)
    assert_select ".post-content .card-player .player-series", 0

    get post_path(a_post("audio", audio: "/media/audio/a.mp3").url_name)
    assert_select ".player-series", 0
  end

  test "[playlist] on a music track lists the release in track order, with this one marked" do
    t2 = a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2, duration: "3:10")
    t1 = a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1)
    a_post("music", audio: "/media/audio/x.mp3", release: "other", track_number: 1)

    get post_path(t2.url_name)
    assert_select ".collection.playlist summary", /Tracks/
    assert_equal [ t1.title, t2.title ], css_select(".collection.playlist .player-track").map { |row| row["data-title"] }
    assert_select ".player-track.is-current[data-title=?]", t2.title
    assert_select ".player-track.is-current .player-track-duration", "3:10"
  end

  test "[playlist] is left out for a release of one, and when the writing has a playlist" do
    alone = a_post("music", audio: "/media/audio/a.mp3", release: "single", track_number: 1)
    get post_path(alone.url_name)
    assert_select ".collection.playlist", 0

    playlist = "Notes.\n\n```collection\ntemplate: playlist\nsource: posts\npost_type: music\nrelease: ep\norder: track_number\n```\n"
    t1 = a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1, content: playlist)
    a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2)
    get post_path(t1.url_name)
    assert_select ".collection.playlist", 1, "the writing's, not the layout's as well"
    assert_select "ol.player-tracks", 1
  end

  test "an episodic show's playlist runs newest first, a serial show's oldest first" do
    old = a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01")
    new = a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01")

    get post_path(old.url_name)
    assert_equal [ new.title, old.title ], css_select(".collection.playlist .player-track").map { |row| row["data-title"] }

    PodcastConfig.stubs(:get).returns({ "type" => "serial" })
    get post_path(old.url_name)
    assert_equal [ old.title, new.title ], css_select(".collection.playlist .player-track").map { |row| row["data-title"] }
  end

  test "a playlist row with no episode or track number shows none, not its position" do
    a_post("podcast", audio: "/media/audio/1.mp3", podcast: "show", date: "2024-01-01", episode_number: 1)
    unnumbered = a_post("podcast", audio: "/media/audio/2.mp3", podcast: "show", date: "2024-02-01")

    get post_path(unnumbered.url_name)
    assert_equal [ "", "E1" ], css_select(".collection.playlist .player-track-number").map(&:text)
  end

  test "a player card and a playlist collection in the writing stand in for the layout's" do
    card = "```card\ntype: player\n```\n\n```collection\nsource: posts\npost_type: podcast\npodcast: show\n" \
           "order: date-asc\ntemplate: playlist\nfold: false\n```\n\nNotes."
    a_post("podcast", audio: "/media/audio/9.mp3", podcast: "show", date: "2024-01-01", season: 1, episode_number: 9)
    ten = a_post("podcast", audio: "/media/audio/10.mp3", podcast: "show", date: "2024-02-01", season: 1, episode_number: 10, content: card)

    get post_path(ten.url_name)
    assert_select ".card-player .player-now-episode", "S1E10"
    assert_select ".card-player .player-playlist", 0, "the player and the list are separate"
    assert_select ".collection.playlist details.player-playlist[open] .player-track", 2, "fold: false opens it on a post"
    assert_equal %w[S1E9 S1E10], css_select(".player-track-number").map(&:text)
    assert_select ".post-player", 0, "the body's card stands in for the layout's player"
    assert_select ".collection.playlist", 1, "and its playlist for the layout's"
  end

  test "a playlist row links to its post with ?play, and its audio is kept but hidden" do
    a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1)
    b = a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2)
    list = "```collection\nsource: posts\npost_type: music\nrelease: ep\ntemplate: playlist\n```\n"
    page = create(:page, metadata: { "title" => "List only", "url_name" => "list-only", "status" => "published" }, content: list)

    get "/#{page.url_name}"
    row = css_select(".player-track").find { |r| r["data-title"] == b.title }
    link = row.at_css("a.player-track-link")
    assert_equal "#{post_path(b.url_name)}?play", link["href"]
    assert_nil link["target"], "without a player it opens in the same tab"
    assert_select "audio.player-track-audio[hidden][src='/media/audio/b.mp3']", 1
    assert_select "audio.player-track-audio[controls]", 0, "no browser audio bar per row"
  end

  test "a playlist from one release is named after it; a mixed one isn't" do
    ReleaseConfig.stubs(:get).with("ep").returns({ "title" => "Soft Sphinx Energy" })
    ReleaseConfig.stubs(:get).with("other").returns({ "title" => "Other" })
    a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1)
    a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2)
    one = "```collection\nsource: posts\npost_type: music\nrelease: ep\ntemplate: playlist\n```\n"
    page = create(:page, metadata: { "title" => "Named", "url_name" => "named", "status" => "published" }, content: one)
    get "/#{page.url_name}"
    assert_select "details.player-playlist summary", text: /\ATracks\s*2 - Soft Sphinx Energy\z/
    assert_select "summary .player-playlist-release", "Soft Sphinx Energy"

    a_post("music", audio: "/media/audio/c.mp3", release: "other", track_number: 1)
    page.update!(content: "```collection\nsource: posts\npost_type: music\ntemplate: playlist\n```\n")
    get "/#{page.url_name}"
    assert_select "summary .player-playlist-release", 0, "tracks from two releases have no one name"
  end

  test "a playlist from one podcast is named after it" do
    PodcastConfig.stubs(:get).returns({ "title" => "The Briefcase" })
    a_post("podcast", audio: "/media/audio/a.mp3", podcast: "brief", episode_number: 1)
    a_post("podcast", audio: "/media/audio/b.mp3", podcast: "brief", episode_number: 2)
    list = "```collection\nsource: posts\npost_type: podcast\ntemplate: playlist\n```\n"
    page = create(:page, metadata: { "title" => "Eps", "url_name" => "eps", "status" => "published" }, content: list)
    get "/#{page.url_name}"
    assert_select "details.player-playlist summary", text: /\AEpisodes\s*2 - The Briefcase\z/
    assert_select "summary .player-playlist-podcast", "The Briefcase"
  end

  test "fold: true folds a playlist collection on a page" do
    a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1)
    a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2)
    list = "```collection\nsource: posts\npost_type: music\nrelease: ep\ntemplate: playlist\n%s```\n"
    page = create(:page, metadata: { "title" => "Folded", "url_name" => "folded", "status" => "published" }, content: format(list, "fold: true\n"))
    get "/#{page.url_name}"
    assert_select "details.player-playlist:not([open])", 1
    assert_select "details.player-playlist summary", /Tracks/

    page.update!(content: format(list, ""))
    get "/#{page.url_name}"
    assert_select "details.player-playlist[open]", 1, "open by default on a page"
  end

  test "the music layout's own player links the tracks before and after it" do
    a_post("music", audio: "/media/audio/a.mp3", release: "ep", track_number: 1)
    t2 = a_post("music", audio: "/media/audio/b.mp3", release: "ep", track_number: 2)
    a_post("music", audio: "/media/audio/c.mp3", release: "ep", track_number: 3)

    get post_path(t2.url_name)
    assert_select ".post-player .player-series-prev", 1
    assert_select ".post-player .player-series-next", 1
  end
end
