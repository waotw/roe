# Finds external http(s) media referenced across content — frontmatter media
# fields and markdown/HTML in the body — for posts, pages, and products.
# Reads the files (single source of truth for the later rewrite). Pure: no
# downloads, no writes.
class MediaImporter::Scanner
  DEFAULT_MODELS = [ Post, Page, Product ].freeze

  def self.scan(models: DEFAULT_MODELS)
    new(models).scan
  end

  # { images: {urls:, records:}, audio: {...}, video: {...} } — unique-URL and
  # affected-record counts per type, for the preview screen.
  def self.summary(refs)
    refs.group_by(&:type).transform_values do |group|
      { urls: group.map(&:url).uniq.size, records: group.map(&:record).uniq.size }
    end
  end

  def initialize(models)
    @models = models
  end

  def scan
    refs = []
    @models.each do |model|
      model.find_each { |record| refs.concat(refs_for(record)) }
    end
    refs.concat(podcast_artwork_refs)
    refs
  end

  private

  # Show-level artwork in podcast.yml that's still an external URL. One shared
  # target (the file) so the rewrite touches podcast.yml once.
  def podcast_artwork_refs
    return [] unless File.exist?(PodcastConfigSeeder::PODCAST_YML)

    target = MediaImporter::ConfigTarget.new(
      PodcastConfigSeeder::PODCAST_YML,
      resync: -> { SiteConfig.sync_from_file("features/podcast") }
    )
    PodcastConfig.all_podcasts.filter_map do |key, cfg|
      artwork = cfg.is_a?(Hash) ? cfg["artwork"].to_s : ""
      next unless MediaImporter.external?(artwork)
      MediaImporter::Ref.new(url: artwork, type: :images, record: target, location: "artwork (#{key})")
    end
  end

  def refs_for(record)
    path = MediaImporter.content_path(record)
    return [] unless path && File.exist?(path)

    fm, body = MediaImporter.split_frontmatter(File.read(path))
    frontmatter_refs(fm, record) + body_refs(body, record)
  end

  def frontmatter_refs(frontmatter, record)
    refs = []
    frontmatter.each do |field, value|
      values = value.is_a?(Array) ? value : [ value ]
      values.each do |v|
        next unless MediaImporter.external?(v)
        type = MediaImporter.media_type(v, field: field)
        refs << MediaImporter::Ref.new(url: v, type: type, record: record, location: field.to_s) if type
      end
    end
    refs
  end

  def body_refs(body, record)
    refs = []
    MediaImporter.image_urls(body).each do |url|
      refs << MediaImporter::Ref.new(url: url, type: :images, record: record, location: :body) if MediaImporter.external?(url)
    end
    MediaImporter.link_urls(body).each do |url|
      next unless MediaImporter.external?(url)
      type = MediaImporter.media_type(url)
      refs << MediaImporter::Ref.new(url: url, type: type, record: record, location: :body) if type
    end
    refs
  end
end
