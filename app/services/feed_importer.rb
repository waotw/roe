# Imports a parsed feed (RSS/Atom, from PodcastFeedFetcher/PodcastFeedParser)
# into Roe as draft posts. Two run modes, chosen per import:
#
#   :episodes — items with an audio enclosure → podcast posts (audio referenced
#               remotely; audio_bytes/audio_type carried so a re-published feed
#               stays valid). Skips text-only items. Deduped by guid.
#   :articles — every item → article posts (body from content:encoded /
#               description). Deduped by source_url (the item link), title
#               fallback.
#
# A mixed feed is handled by running twice (episodes then articles); dedup means
# the second pass only picks up what the first didn't. Media stays remote — the
# separate media importer localizes later.
class FeedImporter
  Result = Struct.new(:imported, :skipped, :slugs, keyword_init: true)

  # An item is an episode when it carries an audio enclosure.
  def self.episode?(item)
    item[:enclosure_url].present? && item[:enclosure_type].to_s.start_with?("audio")
  end

  # Composition for the preview screen — counts only, no writes.
  def self.classify(items)
    episodes = Array(items).count { |i| episode?(i) }
    { total: Array(items).size, episodes: episodes, articles: Array(items).size - episodes }
  end

  # feed:        parsed hash ({ channel:, items: })
  # kind:        :articles | :episodes
  # podcast_key: the podcast.yml show key (required for :episodes)
  # limit:       nil = all, Integer = latest N (feeds are newest-first)
  # posts_dir:   overridable so tests can write to a temp dir
  def initialize(feed:, kind:, podcast_key: nil, limit: nil, posts_dir: RoeSitePaths::SITE_POSTS_PATH)
    @items       = Array(feed[:items])
    @kind        = kind.to_sym
    @podcast_key = podcast_key
    @limit       = limit
    @posts_dir   = posts_dir
    @converter   = SubstackImporter::Converter.new(insert_paywalls: false)

    raise ArgumentError, "kind must be :articles or :episodes" unless %i[articles episodes].include?(@kind)
    raise ArgumentError, "episodes need a podcast_key" if @kind == :episodes && podcast_key.blank?
  end

  def import
    result = Result.new(imported: 0, skipped: 0, slugs: [])
    writer = ContentWriter.new(posts_dir: @posts_dir)

    selected.each do |item|
      if already_imported?(item)
        result.skipped += 1
        next
      end

      slug = writer.write(kind: :post, metadata: metadata_for(item), body: body_for(item))
      result.slugs << slug
      result.imported += 1
    rescue => e
      Rails.logger.error "[FeedImporter] #{item[:title].inspect}: #{e.class} #{e.message}"
    end

    result
  end

  # Build one post's [slug, file_content] — the mapping + serialization, no I/O.
  # Public so previews/tests can inspect exactly what would be written (the
  # actual write, with -N disambiguation, goes through ContentWriter).
  def content_for(item)
    metadata = metadata_for(item)
    [ metadata["url_name"], "---\n#{::Post.format_metadata_yaml(metadata)}\n---\n#{body_for(item)}\n" ]
  end

  private

  # Episodes run: only audio items. Articles run: every item (an audio item
  # imported under :articles becomes a plain article). limit = latest N.
  def selected
    items = @kind == :episodes ? @items.select { |i| self.class.episode?(i) } : @items
    @limit ? items.first(@limit) : items
  end

  # Dedupe on the single most-authoritative identifier available. Checking one
  # key (not several OR'd together) matters: feeds like monome reuse the same
  # <link> for every item, so a source_url check would wrongly skip everything
  # after the first — the per-item guid is what's actually unique there.
  def already_imported?(item)
    field, value = dedup_key(item)
    value.present? && ::Post.exists?([ "json_extract(metadata, '$.#{field}') = ?", value ])
  end

  # Priority: guid (RSS's per-item id) → source_url (the item link) → title.
  # Episodes almost always carry a guid; fall back to the audio URL if not.
  # (field is always a controlled literal, never feed input.)
  def dedup_key(item)
    if @kind == :episodes
      item[:guid].present? ? [ "guid", item[:guid] ] : [ "audio", item[:enclosure_url] ]
    elsif item[:guid].present?
      [ "guid", item[:guid] ]
    elsif item[:link].present?
      [ "source_url", item[:link] ]
    else
      [ "title", item[:title].to_s ]
    end
  end

  def metadata_for(item)
    @kind == :episodes ? episode_metadata(item) : article_metadata(item)
  end

  def body_for(item)
    @converter.convert(item[:content_html].presence || item[:description].to_s)
  end

  def base_metadata(item)
    {
      "title"        => item[:title].to_s.strip.presence,
      "url_name"     => slugify(item),
      "date"         => published_at(item[:pub_date]),
      "status"       => "draft",
      "audience"     => "everyone",
      "published_to" => "site",
      "author"       => item[:author].presence,
      "image"        => item[:image_url].presence
    }.compact
  end

  def article_metadata(item)
    base_metadata(item).merge(
      "post_type"  => "article",
      "source_url" => item[:link].presence,
      "guid"       => item[:guid].presence   # kept when present; not required
    ).compact
  end

  def episode_metadata(item)
    base_metadata(item).merge(
      "post_type"      => "podcast",
      "podcast"        => @podcast_key,
      "audio"          => item[:enclosure_url],
      "audio_bytes"    => item[:enclosure_length],   # nil when the feed omits it
      "audio_type"     => item[:enclosure_type],
      "duration"       => item[:duration].presence,
      "episode_number" => item[:episode].presence,
      "season"         => item[:season].presence,
      "episode_type"   => item[:episode_type].presence,
      "explicit"       => normalize_explicit(item[:explicit]),
      "guid"           => item[:guid].presence
    ).compact
  end

  def slugify(item)
    source = item[:title].presence || item[:guid].presence || "item"
    source.parameterize.presence || "item"
  end

  # Roe's podcast schema stores explicit as "true"/"false"; feeds say
  # yes/no/clean/explicit. nil (absent) falls back to the show setting.
  def normalize_explicit(value)
    return nil if value.blank?
    %w[yes true explicit].include?(value.to_s.strip.downcase) ? "true" : "false"
  end

  # The item's publish time from the feed (<pubDate> / <published>), parsed
  # with its own timezone and normalized to UTC — accurate, not guessed. Feeds
  # almost always carry a real time; when one doesn't (or it's unparseable) we
  # fall back to the import time so the draft still sorts sensibly.
  def published_at(raw)
    raw.to_s.strip.present? ? Time.parse(raw).utc.iso8601 : Time.current.utc.iso8601
  rescue ArgumentError
    Time.current.utc.iso8601
  end
end
