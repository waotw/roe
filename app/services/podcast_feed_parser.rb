# Pure parser for podcast feeds. No HTTP, no DB, no I/O — just XML in,
# structured Hash out. Used by both the Substack importer (per-episode
# enrichment) and the podcast.yml seeding flow (channel-level metadata).
#
# Handles two feed formats:
#
#   * RSS 2.0 + iTunes namespace — the canonical podcast format,
#     required by Apple Podcasts/Spotify/Overcast directories. Carries
#     the full iTunes metadata set (explicit, duration, category,
#     owner_email, etc.).
#
#   * Atom 1.0 — what many static-site generators emit by default for
#     blog audio feeds. Atom doesn't conventionally carry iTunes
#     extensions, so iTunes-only fields come back nil from Atom feeds.
#     This is expected, not a bug — the user fills those in by hand on
#     the podcast settings page after import.
#
# Output shape (stable across both formats):
#   {
#     channel: { title:, description:, ..., image_url: },
#     items:   [ { guid:, substack_post_id:, title:, ..., enclosure_url: }, ... ]
#   }
#
# `substack_post_id` is extracted from Substack's `substack:post:NNN`
# RSS GUID format. For non-Substack RSS feeds and for all Atom feeds
# it's nil — consumers should match by slug / link instead.
class PodcastFeedParser
  ITUNES_NS = { "itunes" => "http://www.itunes.com/dtds/podcast-1.0.dtd" }.freeze

  def self.parse(xml_string)
    new(xml_string).parse
  end

  def initialize(xml_string)
    @xml = xml_string.to_s
  end

  def parse
    doc = Nokogiri::XML(@xml)
    case doc.root&.name
    when "feed" then parse_atom(doc)
    when "rss"  then parse_rss(doc)
    else
      # Unknown root — try RSS as the safer default since it's the
      # historical norm. If there's genuinely no <channel> inside,
      # extract_rss_channel returns {} and the caller's title-blank
      # check fires with a clearer error than parsing garbage would.
      parse_rss(doc)
    end
  end

  private

  def parse_rss(doc)
    {
      channel: extract_rss_channel(doc),
      items:   extract_rss_items(doc)
    }
  end

  def parse_atom(doc)
    # Atom feeds declare their namespace as the default
    # (xmlns="http://www.w3.org/2005/Atom"), which makes prefixed
    # XPath like `//atom:feed` brittle across Nokogiri configurations
    # — some setups don't match the root element via a bound prefix
    # when the document declares the URI as its default namespace.
    # Atom feeds also don't conventionally carry iTunes-extension
    # tags (those are an RSS-extension convention), so there are no
    # foreign-namespaced elements we need to preserve.
    #
    # Strip namespaces on a duped doc and use unprefixed XPath
    # throughout — simpler, and works regardless of how the source
    # declares its default namespace.
    doc = doc.dup
    doc.remove_namespaces!

    {
      channel: extract_atom_channel(doc),
      items:   extract_atom_items(doc)
    }
  end

  # ---------------------------------------------------------------
  # RSS 2.0 (+ iTunes namespace)
  # ---------------------------------------------------------------

  def extract_rss_channel(doc)
    channel = doc.at_xpath("//channel")
    return {} unless channel

    {
      title:       text(channel, "title"),
      description: text(channel, "description"),
      link:        text(channel, "link"),
      language:    text(channel, "language"),
      copyright:   text(channel, "copyright"),
      author:      itunes_text(channel, "author"),
      subtitle:    itunes_text(channel, "subtitle"),
      type:        itunes_text(channel, "type"),
      explicit:    itunes_text(channel, "explicit"),
      owner_name:  channel.at_xpath("itunes:owner/itunes:name", ITUNES_NS)&.text&.strip,
      owner_email: channel.at_xpath("itunes:owner/itunes:email", ITUNES_NS)&.text&.strip,
      category:    channel.at_xpath("itunes:category", ITUNES_NS)&.attribute("text")&.value,
      subcategory: channel.at_xpath("itunes:category/itunes:category", ITUNES_NS)&.attribute("text")&.value,
      image_url:   channel.at_xpath("itunes:image", ITUNES_NS)&.attribute("href")&.value
    }
  end

  def extract_rss_items(doc)
    doc.xpath("//item").map do |item|
      guid = text(item, "guid")
      enclosure = item.at_xpath("enclosure")

      {
        guid:             guid,
        substack_post_id: extract_substack_post_id(guid),
        title:            text(item, "title"),
        description:      text(item, "description"),
        link:             text(item, "link"),
        pub_date:         text(item, "pubDate"),
        author:           itunes_text(item, "author"),
        explicit:         itunes_text(item, "explicit"),
        duration:         itunes_text(item, "duration"),
        image_url:        item.at_xpath("itunes:image", ITUNES_NS)&.attribute("href")&.value,
        enclosure_url:    enclosure&.attribute("url")&.value,
        enclosure_type:   enclosure&.attribute("type")&.value,
        enclosure_length: enclosure&.attribute("length")&.value
      }
    end
  end

  # ---------------------------------------------------------------
  # Atom 1.0
  # ---------------------------------------------------------------

  def extract_atom_channel(doc)
    # After remove_namespaces! in parse_atom, the root <feed> is just
    # doc.root. Defensive name check in case some upstream caller
    # passes us a non-Atom doc.
    feed = doc.root
    return {} unless feed && feed.name == "feed"

    author_name  = feed.at_xpath("author/name")&.text&.strip
    author_email = feed.at_xpath("author/email")&.text&.strip

    {
      # Atom's <subtitle> is the closest semantic match to RSS's channel
      # <description>; populate both so downstream consumers work either way.
      title:       text(feed, "title"),
      description: text(feed, "subtitle"),
      link:        atom_link_href(feed, "alternate"),
      # `xml:lang` is special — even after remove_namespaces! it can be stored
      # as the unprefixed "lang" attribute on the root. Check both.
      language:    feed["xml:lang"] || feed["lang"],
      author:      author_name,
      subtitle:    text(feed, "subtitle"),
      owner_name:  author_name,
      owner_email: author_email,

      # Some feeds are Atom on the outside but carry RSS/iTunes metadata inside
      # (FeedPress, for one). After remove_namespaces! those elements are just
      # unprefixed, so pull them here — each falls back to the pure-Atom
      # equivalent (or nil), so genuine Atom feeds behave exactly as before.
      # (Atom's own <category> uses a `term` attribute, not `text`, so reading
      # the `text` attribute safely ignores it and only catches iTunes ones.)
      copyright:   text(feed, "copyright").to_s.presence || text(feed, "rights"),
      type:        text(feed, "type").to_s.presence,
      explicit:    text(feed, "explicit").to_s.presence,
      category:    feed.at_xpath("category")&.attribute("text")&.value,
      subcategory: feed.at_xpath("category/category")&.attribute("text")&.value,
      # <itunes:image href> first; then Atom's <logo> (large) / <icon> (small).
      image_url:   (feed.at_xpath("image")&.attribute("href")&.value.presence ||
                    text(feed, "logo").to_s.presence ||
                    text(feed, "icon").to_s.presence)
    }
  end

  def extract_atom_items(doc)
    return [] unless doc.root

    doc.root.xpath("entry").map do |entry|
      enclosure = atom_link_node(entry, "enclosure")

      {
        # Atom's <id> is the equivalent of RSS's <guid>. Carries
        # urn:uuid:, tag:, or any opaque URI.
        guid:             text(entry, "id"),
        substack_post_id: nil,

        title:            text(entry, "title"),

        # Prefer <content> when present (full body) since podcast
        # episode descriptions tend to be substantial; fall back to
        # <summary> for feeds that only carry the shorter form.
        description:      text(entry, "content") || text(entry, "summary"),

        link:             atom_link_href(entry, "alternate"),

        # Atom prefers <published> for original publish date and
        # <updated> for last edit. RSS callers expect a single
        # pub_date string, so fall through if published is absent.
        pub_date:         text(entry, "published") || text(entry, "updated"),

        author:           entry.at_xpath("author/name")&.text&.strip,
        explicit:         nil,
        duration:         nil,
        image_url:        nil,

        enclosure_url:    enclosure&.attribute("href")&.value,
        enclosure_type:   enclosure&.attribute("type")&.value,
        enclosure_length: enclosure&.attribute("length")&.value
      }
    end
  end

  # ---------------------------------------------------------------
  # Shared helpers
  # ---------------------------------------------------------------

  def extract_substack_post_id(guid)
    return nil unless guid
    m = guid.match(/\Asubstack:post:(\d+)\z/)
    m && m[1]
  end

  def text(node, name)
    node.at_xpath(name)&.text&.strip
  end

  def itunes_text(node, name)
    node.at_xpath("itunes:#{name}", ITUNES_NS)&.text&.strip
  end

  # Find an <link rel="X"> child node. Atom allows multiple <link>
  # elements per parent (one per rel); we pick the first match.
  # Used post-remove_namespaces, so no prefix needed.
  def atom_link_node(node, rel)
    node.at_xpath("link[@rel='#{rel}']")
  end

  # Just the href attribute from the matching link, since callers
  # typically only need the URL.
  def atom_link_href(node, rel)
    atom_link_node(node, rel)&.attribute("href")&.value
  end
end
