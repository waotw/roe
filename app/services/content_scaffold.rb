# The starter markdown a new post, page, or product is created with.
#
# Roe renders content from markdown, so the elements a type needs — a player, a
# track list, a buy button — are fenced blocks in the body rather than machinery
# in a template. Writing them in at create time means a new podcast episode
# arrives with a working player instead of the author having to know the block
# syntax, while everything stays plain markdown they can edit or delete.
#
# There is deliberately NO placeholder syntax. Blocks are live: `card type:
# player` resolves the post's audio at render, so it can't go stale. Values that
# would be frozen into the body (a title, an image path) are only written where
# the type actually needs them there.
#
# WHICH BLOCKS: per-post-type lists live in Post::POST_TYPES[:scaffold] next to
# that type's metadata_fields; pages and products don't vary, so they're below.
# `:content` marks where the editable template body goes — for a podcast the
# player sits above it and the episode list below, mirroring the layout this
# replaces.
#
# A block that needs a value it doesn't have is skipped rather than written
# empty: no playlist until we know which podcast, no image tag until there's an
# image. The author fills the field in and adds the block from the builder.
class ContentScaffold
  # Pages and products have no sub-types.
  #
  # Posts get no `# title` — the post layout renders it from metadata
  # (posts/_header.html.erb). Pages and products DO, because their views don't:
  # a page leaves its title to the markdown, and a product's first <h1> is what
  # products_helper#product_content tags as the title.
  SCAFFOLDS = {
    "page"    => [ :title, :content ],
    "product" => [ :image, :title, :content, :buy_button ]
  }.freeze

  DEFAULT = [ :content ].freeze

  def self.body_for(type, metadata: {}, template_body: "")
    new(type, metadata, template_body).body
  end

  def initialize(type, metadata, template_body)
    @type = type.to_s
    @metadata = metadata.is_a?(Hash) ? metadata : {}
    @template_body = template_body.to_s
  end

  def body
    parts = blocks.map { |block| render(block) }.compact.reject(&:empty?)
    return @template_body if parts.empty?

    "\n#{parts.join("\n\n")}\n"
  end

  private

  def blocks
    if @type == "post"
      post_type = @metadata["post_type"].presence || "article"
      config = Post::POST_TYPES[post_type.to_sym]
      Array(config && config[:scaffold]).presence || DEFAULT
    else
      SCAFFOLDS.fetch(@type, DEFAULT)
    end
  end

  def render(block)
    case block
    when :content    then @template_body.strip
    when :title      then title.present? ? "# #{title}" : nil
    when :image      then image_block
    when :player     then fence("card", [ "type: player" ])
    when :playlist   then playlist_block
    # A bare button IS a product button, and it finds the product it's on, so
    # no sku is needed here. The price shows by default.
    when :buy_button then fence("button", [ "text: Add to Cart" ])
    end
  end

  def title
    @metadata["title"].to_s.strip
  end

  # Skipped until there's an image — an empty src renders a broken image.
  def image_block
    image = @metadata["image"].to_s.strip
    return nil if image.empty?

    "![#{title.presence || 'Image'}](#{image})"
  end

  # A playlist has to know what to gather. The association key is on the post
  # (`podcast:` / `release:`); without it the collection would list every
  # episode on the site, so skip it instead.
  def playlist_block
    post_type = @metadata["post_type"].to_s
    key_field = post_type == "music" ? "release" : "podcast"
    key = @metadata[key_field].to_s.strip
    return nil if key.empty?

    order = post_type == "music" ? "track_number" : "episode_number"
    fence("collection", [
      "template: playlist",
      "source: posts",
      "post_type: #{post_type}",
      "#{key_field}: #{key}",
      "order: #{order}"
    ])
  end

  def fence(kind, lines)
    "```#{kind}\n#{lines.join("\n")}\n```"
  end
end
