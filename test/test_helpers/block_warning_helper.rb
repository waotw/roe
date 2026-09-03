# frozen_string_literal: true

# Roe explains a block it couldn't render with an amber warning box, and those
# boxes must reach the author and nobody else.
#
# The trap this exists to close: warnings render when Rails.env.development? or
# it's a preview, and the test environment is neither. So `assert_no_match` on a
# plain to_html passes whether or not the suppression works — it passes when the
# warning was never generated at all. Every negative context below is therefore
# rendered under a stubbed development environment, where the warning would be
# on and something has to actively suppress it.
#
# The one exception is :published, which is the production case — there the
# environment IS the suppression, and that's the claim being made.
module BlockWarningHelper
  # context => [warning expected?, rendered in development?]
  #
  # :static and :feed are checked in development because that is the only place
  # their guard does any work. A feed rendered on a dev machine once shipped
  # "Stripe isn't connected" into content:encoded and it arrived in a reader.
  WARNING_CONTEXTS = {
    preview:     [ true,  false ],
    development: [ true,  true  ],
    published:   [ false, false ],
    static:      [ false, true  ],
    feed:        [ false, true  ]
  }.freeze

  def render_block(content, context:, metadata: {})
    post = Post.new(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "block-warning.md"),
      content: content,
      metadata: { "title" => "Block Warning", "url_name" => "block-warning",
                  "status" => "published" }.merge(metadata)
    )

    _, in_development = WARNING_CONTEXTS.fetch(context) do
      raise ArgumentError, "unknown context #{context.inspect}"
    end

    render = -> do
      case context
      when :preview then post.to_html(preview: true)
      when :static  then post.to_html(static: true)
      when :feed    then post.to_html(feed: true)
      else               post.to_html
      end
    end

    in_development ? with_development(&render) : render.call
  end

  # Asserts a warning reaches the author in every context that is the author,
  # and no context that is a reader. Both halves matter: a warning nobody sees
  # is the bug this feature was built to fix, and one a reader sees is worse
  # than the block rendering empty.
  def assert_block_warning(content, matching:, metadata: {})
    WARNING_CONTEXTS.each do |context, (expected, _)|
      html = render_block(content, context: context, metadata: metadata)

      if expected
        assert_match matching, html,
          "no warning in #{context} — the author has no way to learn about this"
      else
        assert_no_match matching, html,
          "the warning reached #{context}, where a reader would see it"
        assert_no_match(/⚠️/, html, "a warning marker reached #{context}")
      end
    end
  end

  # For a block that is fine: nothing should warn anywhere, including the two
  # contexts where warnings are on.
  def assert_no_block_warning(content, metadata: {})
    WARNING_CONTEXTS.each_key do |context|
      assert_no_match(/⚠️/, render_block(content, context: context, metadata: metadata),
        "unexpected warning in #{context}")
    end
  end

  private

  def with_development
    Rails.env.stubs(:development?).returns(true)
    yield
  ensure
    Rails.env.unstub(:development?)
  end
end
