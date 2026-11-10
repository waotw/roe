# Body wins: when the writing already has a player card, a playlist or a buy
# button, the layout leaves out its own, so nothing shows twice. Only those:
# a title or image written in the body as well shows twice, which is plain to
# see and fix, where two players or two buttons would be confusing. Older
# posts carry no blocks and get the layout's parts; posts written since the
# scaffolds carry theirs in the body.
#
# A text scan of the raw Markdown, before it's rendered — no rendering and no
# database work, so it costs next to nothing per page.
class ContentLayout
  class BodyCheck
    def initialize(record)
      @record = record
      @text = record.respond_to?(:content) ? record.content.to_s : ""
    end

    def has?(part)
      case part.to_s
      when "player"     then player?
      when "playlist"   then playlist?
      when "buy_button" then buy_button?
      else false
      end
    end

    private

    # The post's own player card; one playing another file doesn't count
    # (Post#own_player_card_in_body?, the rule the old templates used).
    # A post's own player is a card playing its audio or video. A page has
    # none of its own, so any player card in its body is its player.
    def player?
      if @record.respond_to?(:own_player_card_in_body?)
        @record.own_player_card_in_body?
      else
        blocks("card").any? { |config| config.match?(/^\s*type:\s*["']?player\b/) }
      end
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

    # The insides of every ```name fence. A block shown as an example inside
    # a longer fence (```` or ~~~) in the docs isn't a block, so those
    # fences are taken out first.
    def blocks(name)
      without_examples.scan(/^```#{name}[ \t]*\r?\n(.*?)^```[ \t]*$/m).map(&:first)
    end

    def without_examples
      @without_examples ||= @text.gsub(/^(`{4,}|~{3,})[^\n]*\n.*?^\1[ \t]*$/m, "")
    end
  end
end
