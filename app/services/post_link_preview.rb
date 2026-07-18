# frozen_string_literal: true

# Derives the values a post-link card would inherit from its referenced item —
# the same fields HasMarkdownExtensions#render_post_link pulls when a card
# gives only `post:`. The card builder fetches these to show as live
# placeholders on the override fields (so authors see what a field will show
# without freezing it into the block).
#
# Reuses the record's own resolve_card_excerpt (from HasMarkdownExtensions) so
# the excerpt matches exactly, and mirrors the renderer's URL / author / date /
# image derivation. Returns nil when the slug resolves to nothing.
class PostLinkPreview
  def self.for(slug)
    new(slug).fields
  end

  def initialize(slug)
    @slug = slug.to_s.strip
  end

  def fields
    record = find_record
    return nil unless record

    data = {
      title:    record.title.presence || "Untitled",
      subtitle: record.metadata["subtitle"].to_s,
      excerpt:  excerpt_for(record),
      # Products carry `description` (posts/pages don't) — surfaced so the
      # product-link builder can placeholder its Description field.
      description: (record.is_a?(Product) ? record.description.to_s : ""),
      url:      url_for(record),
      author:   "",
      date:     "",
      image:    (record.respond_to?(:image) && record.image.present?) ? record.image : ""
    }

    # Author and date are post-only, matching render_post_link.
    if record.is_a?(Post)
      data[:author] = record.author.presence || SiteConfig.get("author").to_s
      data[:date]   = format_date(record.date)
    end

    data
  end

  private

  # Mirrors HasMarkdownExtensions#find_post_by_slug (prefix-stripped url_name
  # across the four content types; bundled Roe docs excluded).
  def find_record
    slug = @slug
      .sub(%r{^/posts/}, "")
      .sub(%r{^/pages/}, "")
      .sub(%r{^/store/}, "")
      .sub(%r{^/documentation/}, "")
      .sub(%r{^/}, "")
    return nil if slug.blank?

    Post.where("json_extract(metadata, '$.url_name') = ?", slug).first ||
      Page.where("json_extract(metadata, '$.url_name') = ?", slug).first ||
      Product.where("json_extract(metadata, '$.url_name') = ?", slug).first ||
      Documentation.where("json_extract(metadata, '$.url_name') = ?", slug)
                   .where("file_path NOT LIKE '%/roe/%'").first
  end

  def url_for(record)
    case record
    when Page          then record.public_url
    when Product       then "/store/#{record.url_name}"
    when Documentation then record.public_url
    else "/posts/#{record.url_name}"
    end
  end

  # Reuse the renderer's own resolver so the placeholder matches what would
  # actually render (metadata excerpt → first prose paragraph, truncated).
  def excerpt_for(record)
    record.send(:resolve_card_excerpt,
                explicit: record.metadata["excerpt"].to_s,
                referenced_post: record,
                max_length: 300)
  rescue StandardError
    record.metadata["excerpt"].to_s
  end

  def format_date(raw)
    return "" if raw.blank?

    parsed = raw.is_a?(Date) ? raw : Date.parse(raw.to_s)
    parsed.strftime("%b %d, %Y")
  rescue StandardError
    raw.to_s
  end
end
