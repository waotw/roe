# frozen_string_literal: true

require "test_helper"

# A dynamically served Roe site had no robots.txt at all — no route, nothing in
# public/ — so there was no opt-out for a crawler to honour even where it would
# have. Only static builds got one, and it said `Allow: /` to everyone.
class RobotsTest < ActionDispatch::IntegrationTest
  def body_after(mode)
    SiteConfig.stubs(:get).with("ai_crawlers").returns(mode)
    SiteConfig.stubs(:get).with("static_generation_enabled").returns(false)
    get "/robots.txt"
    response.body
  end

  test "it is served, as plain text, without signing in" do
    get "/robots.txt"

    assert_response :success
    assert_equal "text/plain", response.media_type
  end

  # Opting in later is a decision someone makes on purpose; opting out later is
  # usually a discovery made too late.
  test "a site with no setting gets the strictest one" do
    SiteConfig.stubs(:get).returns(nil)
    get "/robots.txt"

    assert_includes response.body, "User-agent: GPTBot"
    assert_includes response.body, "User-agent: PerplexityBot", "AI answers too"
  end

  test "block_training leaves the retrieval crawlers alone" do
    body = body_after("block_training")

    assert_includes body, "User-agent: GPTBot"
    assert_not_includes body, "User-agent: PerplexityBot"
    assert_not_includes body, "User-agent: OAI-SearchBot"
  end

  test "allow writes no crawler rules at all" do
    body = body_after("allow")

    assert_not_includes body, "GPTBot"
    assert_no_match(/^Disallow: \/$/, body, "nothing is blanket-disallowed")
    assert_includes body, "User-agent: *"
  end

  # The whole point of Google-Extended and Applebot-Extended is refusing AI
  # training without falling out of search. Blocking the parent agent instead
  # would drop the site from Google, Bing or Apple results entirely.
  test "ordinary search engines are never blocked" do
    body = body_after("block_all")

    %w[Googlebot Bingbot Applebot DuckDuckBot].each do |agent|
      assert_no_match(/^User-agent: #{agent}$/, body, "#{agent} must not be disallowed")
    end

    assert_includes body, "User-agent: Google-Extended", "the training-only token is the one to block"
    assert_includes body, "User-agent: Applebot-Extended"
  end

  test "every crawler named gets a rule, and the catch-all comes last" do
    body = body_after("block_all")

    AiCrawlers.blocked("block_all").each do |agent|
      assert_includes body, "User-agent: #{agent}\nDisallow: /"
    end
    assert_equal AiCrawlers.blocked("block_all").size + 1, body.scan(/^User-agent: /).size,
      "one stanza each, plus the catch-all"
    assert_match(/User-agent: \*\n(Disallow: \S+\n)*Allow: \/\n\z/, body.sub(/\n+\z/, "\n"))
  end

  # %w[] splits on whitespace, so three agents with spaces in their names were
  # being written out as separate stanzas — including a bare "Bot" rule, which
  # is meaningless and a hazard in a file that decides who gets shut out.
  test "an agent name with a space in it stays one agent" do
    body = body_after("block_all")

    [ "Kangaroo Bot", "Poseidon Research Crawler", "Sidetrade indexer bot" ].each do |agent|
      assert_includes AiCrawlers::TRAINING, agent
      assert_includes body, "User-agent: #{agent}\nDisallow: /"
    end

    (AiCrawlers::TRAINING + AiCrawlers::RETRIEVAL).each do |agent|
      assert_operator agent.length, :>, 3, "#{agent.inspect} is too generic to be a real agent name"
    end
  end

  # A Sitemap line pointing at a 404 is worse than no line — only static builds
  # produce one.
  test "no sitemap is advertised unless static generation makes one" do
    assert_not_includes body_after("allow"), "Sitemap:"

    SiteConfig.stubs(:get).with("ai_crawlers").returns("allow")
    SiteConfig.stubs(:get).with("static_generation_enabled").returns(true)
    SiteConfig.stubs(:get).with("url").returns("https://example.com/")
    get "/robots.txt"

    assert_includes response.body, "Sitemap: https://example.com/sitemap.xml"
  end

  # A data file, not a page — it has no business in search results, whatever the
  # AI setting says. Readers are unaffected: robots.txt governs crawlers, not
  # the fetch the search UI makes from the browser.
  test "the search index is disallowed for every crawler, in every mode" do
    AiCrawlers::MODES.each do |mode|
      assert_includes body_after(mode), "Disallow: /search-index.json", "missing in #{mode}"
    end
  end

  test "an unrecognised setting falls back to the strictest, not to allow" do
    assert_includes body_after("nonsense"), "User-agent: GPTBot"
  end
end
