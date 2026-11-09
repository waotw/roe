# Body wins: when a post's own writing already has a part, the layout's copy
# is skipped, so nothing shows twice. Older posts carry no blocks and get the
# layout's parts; posts written since the scaffolds carry theirs in the body.
#
# A text scan of the raw Markdown, before it's rendered — no rendering and no
# database work, so it costs next to nothing per page.
class ContentLayout
  class BodyCheck
    FENCED_CODE = /^(`{3,}|~{3,})[^\n]*\n.*?^\1[ \t]*$/m

    def initialize(record)
      @record = record
      @text = record.respond_to?(:content) ? record.content.to_s : ""
    end

    def has?(part)
      case part.to_s
      when "player"     then player?
      when "playlist"   then playlist?
      when "buy_button" then buy_button?
      when "title"      then @record.is_a?(Product) && heading?
      when "image"      then @record.is_a?(Product) && leading_image?
      else false
      end
    end

    private

    # The post's own player card; one playing another file doesn't count
    # (Post#own_player_card_in_body?, the rule the old templates used).
    def player?
      @record.respond_to?(:own_player_card_in_body?) && @record.own_player_card_in_body?
    end

    # A playlist collection, or a player card showing its own.
    def playlist?
      blocks("collection").any? { |config| config.match?(/^\s*template:\s*["']?playlist\b/) } ||
        blocks("card").any? { |config| config.match?(/^\s*show_playlist:\s*["']?true\b/) }
    end

    # A product button is a ```button with no `for:`/`type:` naming another
    # kind (share, subscribe, …) — the same default process_buttons uses.
    def buy_button?
      blocks("button").any? do |config|
        kind = config[/^\s*(?:for|type):\s*["']?([a-z_]+)/, 1]
        kind.nil? || kind == "product"
      end
    end

    def heading?
      without_code.match?(/^#[ \t]+\S/)
    end

    # An image or gallery as the first thing in the body — where the product
    # scaffold puts it, and what product_content treats as the product image.
    def leading_image?
      first = @text.lstrip.lines.first.to_s.strip
      first.start_with?("![", "```gallery", "<img", "<picture", "<figure")
    end

    # The insides of every ```name fence. A block shown as an example inside
    # a longer fence (```` or ~~~) in the docs isn't a block, so those
    # fences are taken out first.
    def blocks(name)
      without_examples.scan(/^```#{name}[ \t]*\r?\n(.*?)^```[ \t]*$/m).map(&:first)
    end

    def without_examples
      @without_examples ||= @text.gsub(/^(`{4,}|~{3,})[^\n]*\n.*?^\1[ \t]*$/m, "")
    end

    def without_code
      @without_code ||= @text.gsub(FENCED_CODE, "")
    end
  end
end
