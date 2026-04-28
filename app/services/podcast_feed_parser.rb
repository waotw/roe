# Pure parser for podcast RSS feeds. No HTTP, no DB, no I/O — just XML in,
# structured Hash out. Used by both the Substack importer (per-episode
# enrichment) and the podcast.yml seeding flow (channel-level metadata).
#
# Output shape:
#   {
#     channel: { title:, description:, ..., image_url: },
#     items:   [ { guid:, substack_post_id:, title:, ..., enclosure_url: }, ... ]
#   }
#
# `substack_post_id` is extracted from Substack's `substack:post:NNN` GUID
# format. For non-Substack feeds it's nil and consumers should match by
# slug / link instead.
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
    {
      channel: extract_channel(doc),
      items: extract_items(doc)
    }
  end

  private

  def extract_channel(doc)
    channel = doc.at_xpath("//channel")
    return {} unless channel

    {
      title: text(channel, "title"),
      description: text(channel, "description"),
      link: text(channel, "link"),
      language: text(channel, "language"),
      copyright: text(channel, "copyright"),
      author: itunes_text(channel, "author"),
      subtitle: itunes_text(channel, "subtitle"),
      type: itunes_text(channel, "type"),
      explicit: itunes_text(channel, "explicit"),
      owner_name: channel.at_xpath("itunes:owner/itunes:name", ITUNES_NS)&.text&.strip,
      owner_email: channel.at_xpath("itunes:owner/itunes:email", ITUNES_NS)&.text&.strip,
      category: channel.at_xpath("itunes:category", ITUNES_NS)&.attribute("text")&.value,
      subcategory: channel.at_xpath("itunes:category/itunes:category", ITUNES_NS)&.attribute("text")&.value,
      image_url: channel.at_xpath("itunes:image", ITUNES_NS)&.attribute("href")&.value
    }
  end

  def extract_items(doc)
    doc.xpath("//item").map do |item|
      guid = text(item, "guid")
      enclosure = item.at_xpath("enclosure")

      {
        guid: guid,
        substack_post_id: extract_substack_post_id(guid),
        title: text(item, "title"),
        description: text(item, "description"),
        link: text(item, "link"),
        pub_date: text(item, "pubDate"),
        author: itunes_text(item, "author"),
        explicit: itunes_text(item, "explicit"),
        duration: itunes_text(item, "duration"),
        image_url: item.at_xpath("itunes:image", ITUNES_NS)&.attribute("href")&.value,
        enclosure_url: enclosure&.attribute("url")&.value,
        enclosure_type: enclosure&.attribute("type")&.value,
        enclosure_length: enclosure&.attribute("length")&.value
      }
    end
  end

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
end
