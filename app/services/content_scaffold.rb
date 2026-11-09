# The starter markdown a new post, page, or product is created with.
#
# What a type shows around its writing — title, player, playlist, buy button —
# comes from its content layout, so the body starts as just the writing. The
# exception is a page's `# title`: the page layout is only its body.
#
# There is deliberately NO placeholder syntax. Values that would be frozen into
# the body (a page's title) are only written where the type actually needs
# them there.
#
# WHICH BLOCKS: per-post-type lists live in Post::POST_TYPES[:scaffold] next to
# that type's metadata_fields; pages and products don't vary, so they're below.
# `:content` marks where the editable template body goes.
#
# Anything the type's content layout already draws (lib/site_templates/
# layouts/content/) stays out of the body: a post's title and player, a
# product's title, image and buy button. Older content with a player card,
# playlist or buy button in its body keeps it, and the layout skips its own
# copy (ContentLayout::BodyCheck); a title or image there shows twice.
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
    end
  end

  def title
    @metadata["title"].to_s.strip
  end
end
