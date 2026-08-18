# frozen_string_literal: true

require "test_helper"

# A mistake in a Roe block config fails quietly: an unknown card type renders
# nothing at all, and a misspelled option is dropped so the block renders as
# though that line was never written. Both leave the writer with no way to tell
# a broken block from one that simply looks like that.
#
# These render with preview: true, which is how the editor renders. The
# published side is covered by BlockWarningsVisibilityTest.
class BlockConfigWarningsTest < ActiveSupport::TestCase
  class TestModel
    include HasMarkdownExtensions
    include HasInlineFootnotes
    attr_accessor :content
    def initialize(content) = @content = content
  end

  # Backticks in a warning render as <code>, so the extracted text has none.
  def warnings(markdown)
    boxes(markdown).map { |d| d.text.gsub(/\s+/, " ").strip }
  end

  def boxes(markdown)
    html = TestModel.new(markdown).to_html(preview: true)
    Nokogiri::HTML::DocumentFragment.parse(html).css("div[style*='dashed']")
  end

  def card(body) = "```card\n#{body}\n```\n"

  test "an unknown card type is named, with the nearest real one" do
    warning = warnings(card("type: pulquote\ntext: Oops.")).first

    assert_includes warning, "Unknown card type"
    assert_includes warning, "Did you mean 'pullquote'?", # the correction, not just a list
      "naming the vocabulary is no help if it doesn't say which one they meant"
  end

  test "a misspelled card option is named, and says it was ignored" do
    warning = warnings(card("type: pullquote\npostion: right\ntext: Hi.")).first

    assert_includes warning, "postion:"
    assert_includes warning, "did you mean position:"
    assert_includes warning, "ignored"
  end

  test "a card missing a required value says which" do
    warning = warnings(card("type: pullquote\nposition: right")).first

    assert_includes warning, "missing a required value"
    assert_includes warning, "text:"
  end

  test "a card needing one of several says so" do
    warning = warnings(card("type: aside\nlink: /somewhere")).first

    assert_includes warning, "at least one of"
    assert_includes warning, "text:"
    assert_includes warning, "image:"
  end

  test "a misspelled collection option is named" do
    warning = warnings("```collection\nsource: posts\nlimitt: 3\n```\n").first

    assert_includes warning, "limitt:"
    assert_includes warning, "did you mean limit:"
  end

  # The warning is prefixed, never substituted. A card with a dropped option
  # still renders — the reader of a published page must see exactly what they
  # saw before, and the writer needs the card itself to judge the problem.
  test "the card still renders alongside its warning" do
    html = TestModel.new(card("type: pullquote\npostion: right\ntext: Still here.")).to_html(preview: true)

    assert_includes html, "Still here."
    assert_includes html, "card-pullquote"
  end

  test "key names in a warning are marked up as code" do
    assert_equal [ "postion:", "position:" ],
      boxes(card("type: pullquote\npostion: right\ntext: Hi.")).first.css("code").map(&:text)
  end

  test "a correct block says nothing" do
    assert_empty warnings(card("type: pullquote\ntext: Fine.\nposition: right"))
    assert_empty warnings(card("type: aside\ntext: Fine."))
    assert_empty warnings(card("type: player\naudio: /media/audio/x.mp3"))
    assert_empty warnings("```collection\nsource: posts\nheading: Recent\nlimit: 3\n```\n")
  end

  # The builder schemas describe what the modal offers; the renderers read a few
  # keys besides. Warning on anything unlisted would flag working markup, and a
  # warning that cries wolf gets ignored along with the ones that matter — so
  # only near-misses are reported.
  test "a working option the builder doesn't offer is not a mistake" do
    assert_empty warnings("```collection\nsource: posts\npart: 2/3\n```\n")
    assert_empty warnings("```collection\nsource: posts\nscope: posts\n```\n")
    assert_empty warnings(card("type: player\naudio: /a.mp3\nvideo: /v.mp4"))
  end

  test "an unrecognised key nothing like a real one is left alone" do
    assert_empty warnings(card("type: pullquote\ntext: Hi.\nzzzzzzzz: value")),
      "Roe doesn't know every key it might be asked to ignore"
  end

  # --- buttons and forms -----------------------------------------------------

  test "a misspelled button option is named with its kind" do
    warning = warnings("```button\nfor: share\nstyl: small\n```\n").first

    assert_includes warning, "styl:"
    assert_includes warning, "share buttons"
    assert_includes warning, "did you mean style:"
  end

  test "a misspelled form option is named with its kind" do
    warning = warnings("```form\nfor: signup\nbutton-txt: Go\n```\n").first

    assert_includes warning, "did you mean button-text:"
  end

  # The renderers read `button-text` and `button_text` alike, so a schema that
  # only lists one spelling must not condemn the other.
  test "either spelling of a hyphenated option is accepted" do
    assert_empty warnings("```form\nfor: signup\nbutton_text: Go\n```\n")
    assert_empty warnings("```form\nfor: signup\nbutton-text: Go\n```\n")
  end

  test "an unknown kind suggests the nearest real one" do
    assert_includes warnings("```button\nfor: prodct\n```\n").first, "Did you mean 'product'?"
    assert_includes warnings("```form\nfor: signupp\n```\n").first, "Did you mean 'signup'?"
  end

  # --- options written on the wrong block ------------------------------------

  # Spelling can't catch these: `sku` is a perfectly good word, just not here.
  # Roe knows exactly where it belongs, so it says so rather than guessing.
  test "an option belonging to another kind is placed, not corrected" do
    warning = warnings("```button\nfor: share\nsku: ABC\n```\n").first

    assert_includes warning, "belongs to product buttons"
    assert_includes warning, "not share buttons"
    assert_not_includes warning, "did you mean"
  end

  test "an option belonging to another card type is placed" do
    warning = warnings(card("type: aside\ntext: Hi.\nattribution: Me")).first

    assert_includes warning, "belongs to pullquote cards"
  end

  test "an option from a different block entirely is placed" do
    warning = warnings(card("type: pullquote\ntext: Hi.\nlimit: 3")).first

    assert_includes warning, "belongs to collection blocks"
  end

  # `text:` is valid on half a dozen blocks. Listing them all buries the only
  # part that matters — not this one.
  test "an option valid in many places is summarised, not enumerated" do
    warning = warnings("```collection\nsource: posts\ntext: Hello\n```\n").first

    assert_includes warning, "other blocks"
    assert_includes warning, "not collection blocks"
  end

  # Every one of these is read by a renderer but absent from the builder modal.
  # Getting them wrong is worse now than it was: a key filed under the wrong
  # block would be confidently reported as belonging somewhere it doesn't.
  test "options the builders don't offer still work on the block that reads them" do
    assert_empty warnings(card("type: player\naudio: /a.mp3\nvideo: /v.mp4"))
    assert_empty warnings(card("type: post-link\npost: x\nsubtitle_from_record: y"))
    assert_empty warnings("```button\nfor: product\nsku: A\nvariants: x\n```\n")
    assert_empty warnings("```collection\nsource: posts\nsearch: true\n```\n")
  end

  # --- galleries -------------------------------------------------------------

  def gallery(body) = "```gallery\n#{body}\n![one](/media/images/a.jpg)\n```\n"

  # Roe calls this a carousel everywhere except the markdown: the builder's
  # checkbox, the docs heading, the rendered class. Only the directive is
  # `slideshow`, so `carousel:` gets typed — and a whitelist parser doesn't
  # merely ignore it, it drops the line entirely.
  test "carousel is named outright, not left to spelling" do
    warning = warnings(gallery("carousel: true")).first

    assert_includes warning, "use slideshow:"
    assert_not_includes warning, "did you mean",
      "Roe knows exactly what this one means"
  end

  test "a misspelled directive is corrected" do
    assert_includes warnings(gallery("captoin: Hello")).first, "did you mean caption:"
    assert_includes warnings(gallery("slidshow: true")).first, "did you mean slideshow:"
  end

  test "a misspelled aspect ratio is corrected" do
    warning = warnings(gallery("aspect_ratio: sqaure")).first

    assert_includes warning, "Unknown aspect ratio"
    assert_includes warning, "Did you mean square"
  end

  # tv/landscape, cinema/film and original/auto are the same shape under two
  # names. The builder offers one of each; the other stays valid to type, and
  # the docs use `film`.
  test "every ratio name the themes define is accepted" do
    GalleryBuilderSchema::RATIOS.each do |ratio|
      assert_empty warnings(gallery("aspect_ratio: #{ratio}")), "#{ratio} should be valid"
    end
  end

  # A theme can define a gallery-ratio class of its own, so this is spell
  # checking, not an allowlist.
  test "a ratio a theme invented is not a mistake" do
    assert_empty warnings(gallery("aspect_ratio: mycrop"))
  end

  test "a correct gallery says nothing" do
    assert_empty warnings(gallery("slideshow: true"))
    assert_empty warnings(gallery("caption: Hello"))
    assert_empty warnings("```gallery\n![one](/media/images/a.jpg)\n```\n")
  end

  # The whitelist exists so `Word: text` stays content rather than becoming
  # config. Prose isn't a mistyped directive and shouldn't be read as one.
  test "prose in a gallery is not treated as a broken directive" do
    assert_empty warnings(gallery("Photos: from the archive"))
  end

  # The dropdown and the directive checking read the same list, so the builder
  # can't offer a shape the renderer ignores.
  test "the builder's ratios are all valid ratios" do
    offered = GalleryBuilderSchema::MENU_RATIOS.map { |r| r[:value] }

    assert_equal offered, offered & GalleryBuilderSchema::RATIOS
  end
end
