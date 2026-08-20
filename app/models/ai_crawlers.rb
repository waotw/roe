# frozen_string_literal: true

# The user agents Roe's robots.txt can ask to stay away, and the honest limits
# of doing so.
#
# robots.txt is a request, not a fence. The large commercial crawlers honour it
# — the legal exposure of being caught ignoring a published opt-out isn't worth
# it to them — and everything else ignores it completely. A scraper that spoofs
# its user agent sees none of this. Content that must not be read by a machine
# belongs behind `audience:`, which is enforced server-side; this is for
# everything you're publishing anyway.
#
# Split in two because they're different asks:
#
#   TRAINING  — collecting pages into a corpus that a model is trained on.
#   RETRIEVAL — fetching a page to answer someone's question right now, usually
#               with a citation and a link back. Blocking these takes the site
#               out of AI answers entirely, which is a real cost and not
#               everyone's intent.
#
# Deliberately absent: Googlebot, Bingbot, Applebot, DuckDuckBot. They're
# ordinary search. `Google-Extended` and `Applebot-Extended` exist precisely so
# a site can refuse AI training without falling out of search results, and
# blocking the parent agent instead would do exactly that.
#
# Names are matched by the crawler against itself, so spelling matters and
# casing doesn't. Sourced from each operator's published documentation and the
# community ai.robots.txt list; new ones appear constantly, so treat this as
# current rather than complete.
module AiCrawlers
  # Quoted rather than %w[] — three of these have spaces in them, and %w splits
  # on whitespace. "Kangaroo Bot" became stanzas for "Kangaroo" and "Bot", and a
  # bare "Bot" rule is both meaningless and a hazard: robots.txt matches agent
  # tokens loosely, so generic fragments are exactly what you don't want in a
  # file that decides who gets shut out.
  # Corpus collection for model training.
  TRAINING = [
    "AI2Bot",
    "Ai2Bot-Dolma",
    "Amazonbot",
    "Andibot",
    "anthropic-ai",
    "Applebot-Extended",
    "Brightbot",
    "Bytespider",
    "CCBot",
    "ChatGLM-Spider",
    "Claude-Web",
    "ClaudeBot",
    "cohere-ai",
    "cohere-training-data-crawler",
    "Crawlspace",
    "Diffbot",
    "FacebookBot",
    "Factset_spyderbot",
    "FirecrawlAgent",
    "Google-CloudVertexBot",
    "Google-Extended",
    "GoogleOther",
    "GPTBot",
    "iaskspider/2.0",
    "ImagesiftBot",
    "ISSCyberRiskCrawler",
    "Kangaroo Bot",
    "magpie-crawler",
    "Meta-ExternalAgent",
    "meta-externalagent",
    "MistralAI-User",
    "NovaAct",
    "omgili",
    "omgilibot",
    "PanguBot",
    "PetalBot",
    "Poseidon Research Crawler",
    "QualifiedBot",
    "Scrapy",
    "SemrushBot-OCOB",
    "SemrushBot-SWA",
    "Sidetrade indexer bot",
    "TikTokSpider",
    "Timpibot",
    "VelenPublicWebCrawler",
    "Webzio-Extended",
    "YouBot"
  ].freeze

  # Live fetches that answer a question and usually cite the source. Blocking
  # these removes the site from AI answers.
  RETRIEVAL = [
    "ChatGPT-User",
    "Claude-SearchBot",
    "Claude-User",
    "DuckAssistBot",
    "LinerBot",
    "Meta-ExternalFetcher",
    "OAI-SearchBot",
    "Operator",
    "Perplexity-User",
    "PerplexityBot",
    "ProRataInc",
    "SearchGPT",
    "YandexAdditional",
    "YandexAdditionalBot"
  ].freeze

  # Paths no crawler should be indexing, whatever the AI setting says. The
  # search index is a data file rather than a page — it has no business in
  # search results, and every crawler that honours robots.txt then leaves it
  # alone. Readers are unaffected: robots.txt governs crawlers, not the fetch
  # the search UI makes from the browser.
  DISALLOWED_PATHS = %w[/search-index.json].freeze

  # What the site.yml setting can be set to, strictest first. `block_all` is the
  # default for a new install: opting in later is a decision someone makes on
  # purpose, where opting out later is usually a discovery made too late.
  MODES = %w[block_all block_training allow].freeze
  DEFAULT_MODE = "block_all"

  # security.yml, falling back to site.yml where it used to live. The boot
  # migration moves it, but a site that hasn't restarted since updating still
  # has it in the old place and must keep working.
  def self.mode
    value = SiteConfig.current("security")&.config&.[]("ai_crawlers")
    value = SiteConfig.get("ai_crawlers") if value.nil? || value.to_s.strip.empty?

    normalised = value.to_s.strip.downcase
    MODES.include?(normalised) ? normalised : DEFAULT_MODE
  rescue StandardError => e
    Rails.logger.warn "[AiCrawlers] falling back to #{DEFAULT_MODE}: #{e.class} #{e.message}"
    DEFAULT_MODE
  end

  # The agents to disallow under a given mode, in the order they're written out.
  def self.blocked(mode = self.mode)
    case mode
    when "block_all"      then TRAINING + RETRIEVAL
    when "block_training" then TRAINING
    else []
    end
  end

  # The whole file. `sitemap_url` is omitted where nothing serves one — a
  # Sitemap line pointing at a 404 is worse than no line.
  def self.robots_txt(mode = self.mode, sitemap_url: nil)
    lines = [ "# Generated by Roe — Admin → Configuration → security.yml" ]

    agents = blocked(mode)
    if agents.any?
      lines << ""
      lines << "# AI crawlers. robots.txt is a request; the large operators"
      lines << "# honour it and anything spoofing its user agent does not."
      agents.each do |agent|
        lines << ""
        lines << "User-agent: #{agent}"
        lines << "Disallow: /"
      end
    end

    lines << ""
    lines << "User-agent: *"
    DISALLOWED_PATHS.each { |path| lines << "Disallow: #{path}" }
    lines << "Allow: /"

    if sitemap_url.present?
      lines << ""
      lines << "Sitemap: #{sitemap_url}"
    end

    lines.join("\n") + "\n"
  end
end
