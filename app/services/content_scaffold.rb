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
# would be frozen into the body (a page's title) are only written where the
# type actually needs them there.
#
# WHICH BLOCKS: per-post-type lists live in Post::POST_TYPES[:scaffold] next to
# that type's metadata_fields; pages and products don't vary, so they're below.
# `:content` marks where the editable template body goes.
#
# Anything the type's content layout already draws (lib/site_templates/
# layouts/content/) stays out of the body: a post's title and player, a
# product's title, image and buy button. Older content with those blocks in
# its body keeps them — the layout skips its own copy (ContentLayout::BodyCheck).
#
# A block that needs a value it doesn't have is skipped rather than written
# empty: no playlist until we know which release. The author fills the field
# in and adds the block from the builder.
class ContentScaffold
  # Pages and products have no sub-types.
  #
  # A page gets its `# title`, because the page layout is only its body. A
  # product's layout draws its title, image and button, so its body is only
  # the writing.
  SCAFFOLDS = {
    "page"    => [ :title, :content ],
    "product" => [ :content ]
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
    when :playlist   then playlist_block
    end
  end

  def title
    @metadata["title"].to_s.strip
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
