require "test_helper"

class HasMarkdownExtensionsTest < ActiveSupport::TestCase
  class TestModel
    include HasMarkdownExtensions
    include HasInlineFootnotes

    attr_accessor :content

    def initialize(content)
      @content = content
    end

    def to_html(preview: false)
      super(preview: preview)
    end
  end

  def render(content, preview: false)
    TestModel.new(content).to_html(preview: preview)
  end

  # =============================================================================
  # Code Block Protection Tests
  # =============================================================================

  # Kramdown wraps the placeholder in a paragraph. <pre> can't live inside <p>,
  # so restoring only the token left `<p><pre>…</pre></p>`, which every later
  # Nokogiri pass rewrote to `<p></p><pre>…</pre>` — a stray empty paragraph
  # before every code block. Hidden by `.content p:empty` in the themes, but
  # present in static builds and newsletter renders where that CSS isn't.
  test "a code block leaves no empty paragraph behind" do
    html = render("Before.\n\n```ruby\nputs \"hi\"\n```\n\nAfter.\n")
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    assert_empty doc.css("p").select { |p| p.children.empty? },
      "the paragraph that wrapped the placeholder should have gone with it"

    # …and the block itself must be untouched by the change.
    assert_equal 1, doc.css("pre code").size
    assert_includes doc.at_css("pre code")["class"].to_s, "ruby"
    assert_includes doc.at_css("pre code").text, 'puts "hi"'
    assert_includes html, "Before."
    assert_includes html, "After."
  end

  test "a code block inside a footnote leaves no empty paragraph" do
    html = render("Text[^fn]\n\n[^fn]: A note:\n\n    ```ruby\n    puts 1\n    ```\n\n    Closing line.\n")
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    assert_empty doc.css(".footnotes p").select { |p| p.children.empty? }
    assert_equal 1, doc.css(".footnotes pre code").size
  end

  # Kramdown doesn't wrap every placement in a paragraph, so the bare-token
  # pass still has to run or the block would never be restored.
  test "a code block inside a list item is still restored" do
    html = render("- An item:\n\n    ```ruby\n    puts 2\n    ```\n")
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    assert_equal 1, doc.css("pre code").size, "the block should render"
    assert_not_includes html, "CODE_BLOCK_PLACEHOLDER",
      "no placeholder token should survive into the output"
  end

  test "several code blocks all restore, with no leftovers" do
    html = render("```ruby\na = 1\n```\n\nMiddle.\n\n```js\nlet b = 2;\n```\n")
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    assert_equal 2, doc.css("pre code").size
    assert_empty doc.css("p").select { |p| p.children.empty? }
    assert_not_includes html, "CODE_BLOCK_PLACEHOLDER"
  end

  # gsub with a STRING replacement reads \0, \1 and \\ as backreferences, so
  # code containing them was silently rewritten. The block form doesn't.
  test "backslash sequences in a code block survive verbatim" do
    # Single-quoted heredoc: what's written here is exactly what's in the file.
    markdown = <<~'MD'
      ```ruby
      text.gsub(/(a)(b)/, "\1-\2")
      ```
    MD

    code = Nokogiri::HTML::DocumentFragment.parse(render(markdown)).at_css("pre code").text

    assert_includes code, '\1-\2',
      "a string replacement would read \\1 as a backreference and drop it"
  end

  test "Roe's own fenced blocks are untouched by code-block restoration" do
    html = render("```card\ntype: player\n```\n")

    assert_includes html, "card-player", "a card block should still render as a card"
    assert_not_includes html, "CODE_BLOCK_PLACEHOLDER"
  end

  test "preserves triple backtick code blocks" do
    content = MarkdownFixture::CODE_BLOCK_RUBY
    result = render(content)

    assert_match(/def hello/, result)
    assert_match(/puts "Hello, World!"/, result)
  end

  test "preserves 4+ backtick code blocks" do
    content = MarkdownFixture::CODE_BLOCK_FOUR_BACKTICKS
    result = render(content)

    assert_match(/Code with four backticks/, result)
  end

  test "code inside collection blocks is processed as markdown" do
    # NOTE: This is current behavior - nested code blocks inside collection blocks
    # are processed as markdown, not preserved as code. This is a known limitation.
    content = <<~MARKDOWN
      ```collection
      ```ruby
      puts "this should stay as code"
      ```
      ```
    MARKDOWN

    result = render(content)

    # The code is processed, not preserved (current implementation limitation)
    # The collection renders with the code block processed
    assert_match(/<div class="collection list"/, result)
  end

  test "code inside card blocks is processed as markdown" do
    # NOTE: This is current behavior - nested code blocks inside card blocks
    # are processed as markdown, not preserved as code. This is a known limitation.
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Something"

      ```ruby
      puts "code in card"
      ```
      ```
    MARKDOWN

    result = render(content)

    # The card renders, and code is processed separately (current implementation limitation)
    assert_match(/class="card card-aside"/, result)
  end

  test "code inside gallery blocks prevents gallery processing" do
    # NOTE: This is current behavior - nested code blocks inside gallery blocks
    # prevent the gallery from being recognized. This is a known limitation.
    content = <<~MARKDOWN
      ```gallery
      ```code
      not an image
      ```
      ```
    MARKDOWN

    result = render(content)

    # The gallery block isn't recognized due to nested code (current limitation)
    # Content is processed as regular markdown instead
    refute_match(/class="gallery"/, result)
    assert_match(/<code>/, result)
  end

  test "complex nested structures preserved" do
    content = <<~MARKDOWN
      # Header

      ```card
      type: pullquote
      text: "Quote"
      ```

      Regular paragraph with `inline code`.

      ```ruby
      class Test
        def method
          puts "code"
        end
      end
      ```
    MARKDOWN

    result = render(content)

    assert_match(/class Test/, result)
    assert_match(/inline code/, result)
    assert_match(/Quote/, result)
  end

  # =============================================================================
  # Footnote Tests
  # =============================================================================

  test "footnote backlink numbers skip nested list items" do
    html = <<~HTML
      <div class="footnotes" role="doc-endnotes">
        <ol>
          <li id="fn:1">
            <p>first footnote</p>
          </li>
          <li id="fn:2">
            <p>second footnote with a list</p>
            <ul>
              <li>list item one</li>
              <li>list item two</li>
            </ul>
          </li>
          <li id="fn:3">
            <p>third footnote</p>
          </li>
        </ol>
      </div>
    HTML

    result = TestModel.new("").send(:add_footnote_backlinks, html)
    doc = Nokogiri::HTML::DocumentFragment.parse(result)
    numbers = doc.css(".footnote-backlink-number").map(&:text)

    # The bug: nested <ul>/<ol> <li>s were counted, making the third
    # footnote render as "5." instead of "3."
    assert_equal [ "1.", "2.", "3." ], numbers
    assert_operator doc.css(".footnotes ul li").count, :>, 0
  end

  test "footnote backlink numbers ignore a nested ORDERED list" do
    html = <<~HTML
      <div class="footnotes" role="doc-endnotes">
        <ol>
          <li id="fn:1">
            <p>first footnote</p>
          </li>
          <li id="fn:2">
            <p>second footnote with an ordered list</p>
            <ol>
              <li>step one</li>
              <li>step two</li>
            </ol>
          </li>
          <li id="fn:3">
            <p>third footnote</p>
          </li>
        </ol>
      </div>
    HTML

    result = TestModel.new("").send(:add_footnote_backlinks, html)
    doc = Nokogiri::HTML::DocumentFragment.parse(result)
    numbers = doc.css(".footnote-backlink-number").map(&:text)

    # The <ul> case above was fixed by selecting `.footnotes ol > li`, but that
    # still matches the items of a nested <ol> — the nested list is itself a
    # descendant of .footnotes, so its <li>s are direct children of *an* ol.
    # Only <ol> triggered it, which is why the earlier fix looked complete.
    assert_equal [ "1.", "2.", "3." ], numbers
    assert_operator doc.css(".footnotes ol ol li").count, :>, 0,
      "the nested list itself should still render"
  end

  test "a footnote referenced twice gets a return link per mention" do
    markdown = <<~MD
      First mention[^reuse] and second mention.[^reuse]

      [^reuse]: Referenced twice.
    MD

    doc = Nokogiri::HTML::DocumentFragment.parse(render(markdown))
    note = doc.at_css(".footnotes > ol > li")

    # Kramdown ids repeat references fnref:name, fnref:name:1, …
    returns = note.css(".footnote-returns .footnote-return")
    assert_equal 2, returns.size, "one return link per mention"
    assert_equal [ "#fnref:reuse", "#fnref:reuse:1" ], returns.map { |a| a["href"] }

    # These have to work with no JavaScript, so they must be real anchors
    # pointing at ids that exist in the document.
    returns.each do |link|
      target = link["href"].sub("#", "")
      assert doc.at_css(%(##{target.gsub(":", "\\\\:")})) || doc.at_css("[id='#{target}']"),
        "return link points at #{target}, which isn't in the document"
    end
  end

  test "a footnote referenced once gets no return links" do
    markdown = <<~MD
      Only mentioned here.[^once]

      [^once]: Referenced once.
    MD

    doc = Nokogiri::HTML::DocumentFragment.parse(render(markdown))

    assert_empty doc.css(".footnote-returns"),
      "single-reference footnotes should keep their markup unchanged"
    assert_equal 1, doc.css(".footnote-backlink-number").size
  end

  test "a footnote containing an ordered list keeps the numbering in step" do
    markdown = <<~MD
      One[^one] two[^two] three[^three]

      [^one]: First note.

      [^two]: Second note, with steps:

          1. Step one
          2. Step two
          3. Step three

      [^three]: Third note.
    MD

    doc = Nokogiri::HTML::DocumentFragment.parse(render(markdown))

    assert_equal 3, doc.css(".footnotes > ol > li").count, "three footnotes, not six"
    assert_equal [ "1.", "2.", "3." ], doc.css(".footnote-backlink-number").map(&:text)
    assert_operator doc.css(".footnotes ol ol li").count, :>, 0,
      "the ordered list inside the footnote should still render"
  end

  # =============================================================================
  # Gallery Tests
  # =============================================================================

  test "manual gallery renders gallery elements" do
    content = MarkdownFixture::GALLERY_SIMPLE
    result = render(content)

    assert_match(/<div class="gallery"/, result)
    assert_match(/<div class="gallery-row gallery-col-3"/, result)
    assert_match(/<img src="mountain.jpg"/, result)
    assert_match(/<img src="ocean.jpg"/, result)
    assert_match(/<img src="forest.jpg"/, result)
  end

  test "manual gallery with multiple images" do
    content = MarkdownFixture::GALLERY_SIMPLE
    result = render(content)

    assert_match(/mountain\.jpg/, result)
    assert_match(/ocean\.jpg/, result)
    assert_match(/forest\.jpg/, result)
  end

  # A caption on a standalone image used to require the `(*…*)` to butt straight
  # up against the `)`. Inside a gallery a space was fine, so the same line
  # captioned one image and printed as italic text beside another — with nothing
  # visible to tell them apart.
  test "a standalone image caption allows a space before it" do
    [ "![alt](/media/images/a.jpg)(*A caption*)",
      "![alt](/media/images/a.jpg) (*A caption*)",
      "![alt](/media/images/a.jpg)\t(*A caption*)" ].each do |line|
      doc = Nokogiri::HTML::DocumentFragment.parse(render("#{line}\n"))

      assert_equal "A caption", doc.at_css("figcaption")&.text,
        "expected a figcaption from: #{line.inspect}"
    end
  end

  # The caption belongs to the image on its line. Allowing any whitespace would
  # let an emphasised paragraph underneath be swallowed as one.
  test "a caption does not reach across a line break" do
    doc = Nokogiri::HTML::DocumentFragment.parse(
      render("![alt](/media/images/a.jpg)\n\n(*Not a caption, just emphasis*)\n"),
    )

    assert_nil doc.at_css("figcaption")
  end

  # A footnote's continuation is indented four spaces, and kramdown ejects
  # anything less back out into the body. The gallery builder writes the block
  # to match; these pin what "match" has to mean, since the builder itself can't
  # be tested here.
  test "a gallery indented into a footnote renders inside it" do
    block = "    ```gallery\n    ![a](/media/images/a.png)\n    ![b](/media/images/b.jpg)\n    ```"

    [ "Text[^1]\n\n[^1]: \n#{block}\n",              # inserted on the line below the marker
      "Text[^1]\n\n[^1]: first line\n#{block}\n",    # after a footnote that already has text
      "Text[^1]\n\n[^1]: \n    ```gallery\n    ![a](/media/images/a.png)\n    aspect_ratio: square\n    ```\n" ].each do |markdown|
      doc = Nokogiri::HTML::DocumentFragment.parse(render(markdown))

      assert_equal 1, doc.css(".footnotes .gallery").size,
        "expected the gallery inside the footnote for:\n#{markdown}"
      assert_equal 1, doc.css(".gallery").size, "and nowhere else"
    end
  end

  # What the builder used to produce. Neither renders a gallery at all — the
  # fence opens on the definition line in one and is indented past its own
  # contents in the other.
  test "a gallery fence sharing the footnote definition line renders nothing" do
    inline = "Text[^1]\n\n[^1]: ```gallery\n![a](/media/images/a.png)\n```\n"
    over_indented = "Text[^1]\n\n[^1]: first\n        ```gallery\n    ![a](/media/images/a.png)\n    ```\n"

    assert_empty Nokogiri::HTML::DocumentFragment.parse(render(inline)).css(".gallery")
    assert_empty Nokogiri::HTML::DocumentFragment.parse(render(over_indented)).css(".gallery")
  end

  test "manual gallery with captions" do
    content = MarkdownFixture::GALLERY_WITH_CAPTIONS
    result = render(content)

    assert_match(/<figcaption>/, result)
    assert_match(/The majestic peak/, result)
    assert_match(/Calm waters/, result)
  end

  test "auto_gallery groups consecutive images" do
    content = MarkdownFixture::CONSECUTIVE_IMAGES
    result = render(content)

    assert_match(/<div class="gallery"/, result)
    assert_match(/photo1\.jpg/, result)
    assert_match(/photo2\.jpg/, result)
    assert_match(/photo3\.jpg/, result)
    # photo4 and photo5 should be in a separate gallery after the text
    assert_match(/photo4\.jpg/, result)
    assert_match(/photo5\.jpg/, result)
  end

  test "auto_gallery breaks on non-image lines" do
    content = MarkdownFixture::CONSECUTIVE_IMAGES
    result = render(content)

    # Should have two separate galleries (two <div class="gallery"> elements)
    gallery_count = result.scan(/<div class="gallery">/).count
    assert_equal 2, gallery_count, "Expected two separate galleries"

    # Photo3 should be in first gallery, Photo4 in second
    assert_match(/photo3\.jpg.*<\/div>\s*<p>Some text between/m, result)
    assert_match(/Some text between.*<div class="gallery">.*photo4\.jpg/m, result)
  end

  test "gallery output has gallery class" do
    content = MarkdownFixture::GALLERY_SIMPLE
    result = render(content)

    assert_match(/class="gallery"/, result)
  end

  test "gallery captions use figcaption" do
    content = MarkdownFixture::GALLERY_WITH_CAPTIONS
    result = render(content)

    assert_match(/<figcaption>The majestic peak<\/figcaption>/, result)
  end

  test "gallery handles single image not as gallery" do
    content = "![Single](single.jpg)"
    result = render(content)

    refute_match(/class="gallery"/, result)
    assert_match(/single\.jpg/, result)
  end

  test "gallery images preserve alt text" do
    content = <<~MARKDOWN
      ```gallery
      ![Mountain Image](mountain.jpg)
      ```
    MARKDOWN

    result = render(content)

    assert_match(/alt="Mountain Image"/, result)
  end

  test "gallery with mixed caption formats" do
    content = <<~MARKDOWN
      ```gallery
      ![With caption](img1.jpg)(*Caption one*)
      ![Without caption](img2.jpg)
      ![Another](img3.jpg)(*Caption three*)
      ```
    MARKDOWN

    result = render(content)

    assert_match(/img1\.jpg/, result)
    assert_match(/img2\.jpg/, result)
    assert_match(/img3\.jpg/, result)
  end

  # =============================================================================
  # Pullquote Card Tests
  # =============================================================================

  test "pullquote center renders card with pullquote classes" do
    content = MarkdownFixture::PULLQUOTE_CENTER
    result = render(content)

    assert_match(/class="card card-pullquote pullquote-center"/, result)
    assert_match(/The only way to do great work/, result)
  end

  test "pullquote left renders floated aside" do
    content = MarkdownFixture::PULLQUOTE_LEFT
    result = render(content)

    assert_match(/pullquote-left/, result)
    assert_match(/Float this to the left/, result)
  end

  test "pullquote right renders floated aside" do
    content = MarkdownFixture::PULLQUOTE_RIGHT
    result = render(content)

    assert_match(/pullquote-right/, result)
    assert_match(/Float this to the right/, result)
  end

  # A floated pullquote is wrapped inside the paragraph that follows it so text
  # runs down both sides, which means breaking that paragraph in two. The break
  # point is chosen from the paragraph's TEXT and used to be applied to its HTML
  # — two different coordinate systems, because the tags aren't in the text. The
  # more markup before the break, the further the offset drifted, until it landed
  # inside a tag and cut it open. A reader hit this with a footnote and saw
  # `class="footnote" rel="footnote" role="doc-noteref">` printed in their post.
  def merged_pullquote(body, footnote: true)
    quote = "```card\ntype: pullquote\nposition: right\ntext: A quote.\n```\n\n"
    note = footnote ? "\n\n[^1]: A note.\n" : "\n"
    doc = Nokogiri::HTML::DocumentFragment.parse(render("#{quote}#{body}#{note}"))
    doc.at_css(".pullquote-merge").tap do |merge|
      assert merge, "expected the pullquote to merge into the paragraph"
    end
  end

  test "the pullquote break never cuts a tag open" do
    # Each emphasis adds tag characters ahead of the break without adding any
    # text, which is exactly what used to drag the offset into a tag.
    [ 0, 1, 3, 6, 10 ].each do |count|
      filler = ([ "*stressed*" ] * count).join(" ")
      merge = merged_pullquote(
        "An opening clause #{filler} runs on for a while before a footnote[^1] " \
        "arrives, and the sentence keeps going long enough afterwards that the " \
        "middle of the paragraph sits somewhere near that reference.",
      )

      assert_no_match(/(?:class|rel|role|href)=/, merge.text,
        "tag attributes leaked into the body text (emphasis=#{count})")
      assert_equal 1, merge.css("a[href^='#fn']").size,
        "the footnote reference should cross the break whole (emphasis=#{count})"
      assert_equal count, merge.css("em").size,
        "emphasis should survive the break (emphasis=#{count})"
    end
  end

  test "the pullquote break loses no words" do
    body = "Sentence one sits before the break. Sentence two has *emphasis* in " \
           "it and a footnote[^1] as well. Sentence three closes it out."
    merge = merged_pullquote(body)

    halves = merge.css("> p")
    assert_equal 2, halves.size, "the paragraph should end up in two halves"

    # The invariant is against the same paragraph with no quote beside it:
    # wrapping one changes where the text breaks, never what the text says.
    alone = Nokogiri::HTML::DocumentFragment.parse(render("#{body}\n\n[^1]: A note.\n"))
    assert_equal alone.at_css("p").text.split(/\s+/),
      halves.map(&:text).join(" ").split(/\s+/),
      "text changed across the break"
  end

  test "a manual || marker breaks where it is written, and does not render" do
    merge = merged_pullquote(
      "The first half is written here. || The second half follows it.",
      footnote: false,
    )

    halves = merge.css("> p")
    assert_equal "The first half is written here.", halves[0].text.strip
    assert_equal "The second half follows it.", halves[1].text.strip
    assert_not_includes merge.text, "||", "the marker is an instruction, not content"
  end

  test "a pullquote before a paragraph too short to break is left alone" do
    quote = "```card\ntype: pullquote\nposition: right\ntext: A quote.\n```\n\n"
    doc = Nokogiri::HTML::DocumentFragment.parse(render("#{quote}Short.\n"))

    # Better an unmerged quote than a wrapper holding an empty paragraph.
    assert_nil doc.at_css(".pullquote-merge")
    assert doc.at_css(".pullquote-right"), "the quote itself still renders"
  end

  test "pullquote with attribution renders cite" do
    content = MarkdownFixture::PULLQUOTE_CENTER
    result = render(content)

    assert_match(/<cite>/, result)
    assert_match(/Steve Jobs/, result)
  end

  test "pullquote without attribution no cite" do
    content = <<~MARKDOWN
      ```card
      type: pullquote
      text: "Quote without attribution"
      position: center
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Quote without attribution/, result)
    refute_match(/<cite>/, result)
  end

  test "pullquote default position is center" do
    content = <<~MARKDOWN
      ```card
      type: pullquote
      text: "No position specified"
      ```
    MARKDOWN

    result = render(content)

    assert_match(/pullquote-center/, result)
  end

  test "pullquote card classes include card and card-pullquote" do
    content = MarkdownFixture::PULLQUOTE_CENTER
    result = render(content)

    assert_match(/class=".*card.*"/, result)
    assert_match(/card-pullquote/, result)
  end

  # =============================================================================
  # Aside Card Tests
  # =============================================================================

  # An aside's text went straight into the HTML, so `*emphasis*` came out with
  # the asterisks showing and a second paragraph never arrived at all — the
  # parser stopped at the first line and dropped the rest.
  def aside(body) = Nokogiri::HTML::DocumentFragment.parse(render("```card\ntype: aside\n#{body}\n```\n"))

  test "an aside holds more than one paragraph" do
    doc = aside("text: text is cool\n\nAnd so is this")

    assert_equal [ "text is cool", "And so is this" ], doc.css(".aside-text p").map(&:text)
  end

  test "an aside renders markdown, not the characters for it" do
    assert_equal "italic", aside("text: This is *italic*").at_css(".aside-text em")&.text
    assert_equal "Bold", aside("text: **Bold** here").at_css(".aside-text strong")&.text
    assert_equal "/docs", aside("text: See [the docs](/docs)").at_css(".aside-text a")&.[]("href")
    assert_equal 2, aside("text: Intro:\n\n- one\n- two").css(".aside-text li").size
  end

  test "an option after the prose is still an option" do
    doc = aside("text: one\n\ntwo\nimage: /media/images/a.jpg")

    assert_equal 2, doc.css(".aside-text p").size
    assert doc.at_css(".aside-image"), "the image is an option, not a third paragraph"
  end

  # Prose opening with "Note:" is a sentence. Option keys are lowercase, which
  # is what tells them apart.
  test "a capitalised word before a colon stays in the text" do
    doc = aside("text: Note: this stays\n\nSecond para")

    assert_equal [ "Note: this stays", "Second para" ], doc.css(".aside-text p").map(&:text)
  end

  # An unrecognised key has to stay a key, or a misspelled option would be
  # silently swallowed into the prose above it instead of being reported.
  test "an unrecognised option does not become part of the text" do
    doc = aside("text: one\n\ntwo\npostion: right")

    assert_equal 2, doc.css(".aside-text p").size
    assert_not_includes doc.text, "postion"
  end

  # Pullquotes read the same `text:`, so they get the paragraphs too — their
  # rendering already ran the text through markdown.
  test "a pullquote holds more than one paragraph" do
    doc = Nokogiri::HTML::DocumentFragment.parse(
      render("```card\ntype: pullquote\ntext: first para\n\nsecond para\nattribution: Me\n```\n"),
    )

    assert_equal [ "first para", "second para" ], doc.css(".card-pullquote p").map(&:text)
    assert_equal "— Me", doc.at_css("cite")&.text
  end

  # An aside points somewhere with `link_url:`, and the card element becomes the
  # anchor rather than wrapping one around the contents — .card-aside is a grid,
  # and an element between it and its children collapses the layout to one
  # column. An <a> can be display:grid and hold flow content, so every existing
  # rule still matches.
  test "link_url makes the whole card a link, image included" do
    doc = aside("image: /media/images/a.jpg\ntext: Read on\nlink_url: /somewhere")
    card = doc.at_css(".card-aside")

    assert_equal "a", card.name
    assert_equal "/somewhere", card["href"]
    assert_includes card["class"], "aside-wrapper"
    assert card.at_css("img"), "the image is inside the link"
  end

  # This did nothing at all before: the link was only ever rendered alongside
  # text, and the image was never wrapped.
  test "an image-only aside can be linked" do
    card = aside("image: /media/images/a.jpg\nlink_url: /somewhere").at_css(".card-aside")

    assert_equal "a", card.name
    assert card.at_css("img")
  end

  # kramdown treats <a> as inline, so an unguarded anchor gets a paragraph
  # wrapped round its opening tag and its closing tag escaped into the page.
  test "a linked aside survives kramdown intact" do
    html = render("Before.\n\n```card\ntype: aside\ntext: Read on\nlink_url: /somewhere\n```\n\nAfter.\n")
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    assert_not_includes doc.text, "</a>", "the closing tag should not be printed as text"
    assert_equal 1, doc.css("a.card-aside").size
  end

  test "link is still accepted as link_url" do
    assert_equal "/somewhere", aside("text: Read on\nlink: /somewhere").at_css(".card-aside")["href"]
  end

  # Written before link_url existed, with its own call-to-action label. Renders
  # exactly as it always did — nothing in the builder writes this any more, but
  # it's sitting in posts.
  test "an aside with link_text keeps its separate link" do
    doc = aside("text: Some text\nlink: /somewhere\nlink_text: Read more")

    assert_equal "div", doc.at_css(".card-aside").name, "the card itself isn't a link"
    assert_equal "Read more", doc.at_css("a.aside-link")&.text
    assert_equal "/somewhere", doc.at_css("a.aside-link")&.[]("href")
  end

  # A link inside a link isn't valid, so the card can't be one when the text
  # already holds one. The image sits outside the text though, so it carries the
  # link instead — the reader gets both, neither nested in the other.
  test "when the text has a link, the image carries link_url" do
    doc = aside("image: /media/images/a.jpg\ntext: See [the docs](/docs)\nlink_url: /somewhere")

    assert_equal "div", doc.at_css(".card-aside").name, "the card itself isn't a link"
    assert_equal "/somewhere", doc.at_css("a.aside-image-link")&.[]("href")
    assert doc.at_css("a.aside-image-link img"), "the image is inside it"
    assert_equal 1, doc.css(".aside-text a").size, "and the text's own link still works"
  end

  # No image and no room in the text — there's nowhere for it to go, which is
  # worth saying rather than dropping in silence.
  test "with no image and a link in the text, link_url has nowhere to go" do
    markdown = "```card\ntype: aside\ntext: See [the docs](/docs)\nlink_url: /somewhere\n```\n"
    doc = Nokogiri::HTML::DocumentFragment.parse(render(markdown, preview: true))

    assert_equal "div", doc.at_css(".card-aside").name
    assert_empty doc.css("a.aside-image-link")
    assert_equal 1, doc.css(".aside-text a").size, "the text's own link still works"
    assert_includes doc.at_css("div[style*='dashed']")&.text.to_s, "Nothing left for link_url"
  end

  # The image only takes the link when the text can't. With plain text the whole
  # card carries it, image included.
  test "plain text leaves the link on the whole card" do
    doc = aside("image: /media/images/a.jpg\ntext: Read on\nlink_url: /somewhere")

    assert_equal "a", doc.at_css(".card-aside").name
    assert_empty doc.css("a.aside-image-link"), "no second link inside it"
  end

  test "aside renders card with aside classes" do
    content = MarkdownFixture::ASIDE_SIMPLE
    result = render(content)

    assert_match(/class="card card-aside"/, result)
    assert_match(/This is an aside/, result)
  end

  test "aside with text only" do
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Simple aside text"
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Simple aside text/, result)
  end

  test "aside with link inline" do
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Learn more"
      link: /related
      ```
    MARKDOWN

    result = render(content)

    assert_match(/href="\/related"/, result)
  end

  test "aside with link and link_text" do
    content = MarkdownFixture::ASIDE_WITH_LINK
    result = render(content)

    assert_match(/href="\/related-page"/, result)
    assert_match(/Read more/, result)
  end

  test "aside with image" do
    content = MarkdownFixture::ASIDE_WITH_IMAGE
    result = render(content)

    assert_match(/class="aside-image"/, result)
    assert_match(/src="\/media\/images\/sidebar\.jpg"/, result)
  end

  test "a link on its own points the whole card, with no arrow appended" do
    content = <<~MARKDOWN
      ```card
      type: aside
      text: "Just text"
      link: /some-page
      ```
    MARKDOWN

    doc = Nokogiri::HTML::DocumentFragment.parse(render(content))

    # `link:` used to turn the text itself into a link and tack an arrow on the
    # end. It now points the whole card instead, so there's no arrow to add and
    # nothing wrapping the text — a link in the text is markdown's job.
    assert_equal "a", doc.at_css(".card-aside").name
    assert_equal "/some-page", doc.at_css(".card-aside")["href"]
    assert_empty doc.css("a.aside-link-inline")
    assert_not_includes doc.at_css(".aside-text").text, "→"
  end

  # =============================================================================
  # Post Link Card Tests
  # =============================================================================

  test "post_link small style" do
    post = create(:post, metadata: {
      "title" => "Hello World",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "hello-world"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: hello-world
      style: small
      ```
    MARKDOWN

    result = render(content)

    assert_match(/post-link-small/, result)
    assert_match(/Hello World/, result)
  end

  test "post_link large style" do
    post = create(:post, metadata: {
      "title" => "Hello World",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "hello-world"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: hello-world
      style: large
      ```
    MARKDOWN

    result = render(content)

    assert_match(/post-link-large/, result)
  end

  test "post_link not found shows error in preview" do
    content = <<~MARKDOWN
      ```card
      type: post-link
      post: nonexistent-post
      style: small
      ```
    MARKDOWN

    # Error only shows in preview mode
    result = render(content, preview: true)

    assert_match(/Content not found: nonexistent-post/, result)
  end

  test "post_link renders link href" do
    post = create(:post, metadata: {
      "title" => "Test Post",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "test-post"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: test-post
      style: small
      ```
    MARKDOWN

    result = render(content)

    assert_match(/href="\/posts\/test-post"/, result)
  end

  test "post_link override title" do
    post = create(:post, metadata: {
      "title" => "Original Title",
      "status" => "published",
      "date" => "2024-01-01",
      "url_name" => "test-post"
    })

    content = <<~MARKDOWN
      ```card
      type: post-link
      post: test-post
      title: Custom Title
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Custom Title/, result)
    refute_match(/Original Title/, result)
  end

  # =============================================================================
  # Inline Collection Tests
  # =============================================================================

  test "collection renders heading" do
    content = <<~MARKDOWN
      ```collection
      heading: Latest Posts
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Latest Posts/, result)
    assert_match(/class="collection list"/, result)
  end

  test "collection with list template" do
    post = create(:post, metadata: {
      "title" => "Test Post",
      "status" => "published",
      "date" => "2024-01-01"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Posts
      template: list
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Test Post/, result)
  end

  test "collection with compact template" do
    post = create(:post, metadata: {
      "title" => "Compact Post",
      "status" => "published",
      "date" => "2024-01-01"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Recent
      template: compact
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Compact Post/, result)
  end

  test "collection with links template" do
    post = create(:post, metadata: {
      "title" => "Links Post",
      "status" => "published",
      "date" => "2024-01-01"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Quick Links
      template: links
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Links Post/, result)
  end

  test "a content id colliding with a reserved mount (snipcart) is namespaced, not dropped" do
    # Body heading: keeps an anchor id, just not the reserved one.
    html = render("## Snipcart")
    refute_match(/id="snipcart"/, html, "must not claim Snipcart's #snipcart cart mount id")
    assert_match(/id="snipcart-section"/, html, "heading stays anchorable under a namespaced id")

    # Collection item title (same auto_id path) — id kept, reserved word dodged.
    create(:post, metadata: {
      "title" => "Snipcart",
      "status" => "published",
      "date" => "2024-01-01",
      "tags" => [ "collide-check" ]
    })

    %w[links list full].each do |template|
      result = render(<<~MARKDOWN)
        ```collection
        template: #{template}
        tags: collide-check
        ```
      MARKDOWN

      assert_match(/class="item-title"/, result, "#{template}: .item-title hook present")
      assert_match(/Snipcart/, result, "#{template}: title still rendered")
      # Whatever the parser slugs the title to, the output must never carry the
      # bare reserved id that Snipcart's cart mount claims.
      refute_match(/id="snipcart"/, result, "#{template}: reserved mount id dodged")
    end
  end

  test "ordinary heading ids are unaffected by the reserved-mount guard" do
    assert_match(/id="getting-started"/, render("## Getting Started"))
  end

  test "collection respects limit" do
    3.times do |i|
      create(:post, metadata: {
        "title" => "Post #{i}",
        "status" => "published",
        "date" => "2024-01-0#{i+1}"
      })
    end

    content = <<~MARKDOWN
      ```collection
      heading: Limited
      limit: 2
      ```
    MARKDOWN

    result = render(content)

    # Collections are ordered by date descending (newest first)
    # Post 2 (Jan 03) and Post 1 (Jan 02) should appear, Post 0 (Jan 01) should not
    assert_match(/Post 2/, result)
    assert_match(/Post 1/, result)
    refute_match(/Post 0/, result)
  end

  test "collection filters by tags" do
    create(:post, metadata: {
      "title" => "Ruby Post",
      "status" => "published",
      "date" => "2024-01-01",
      "tags" => [ "ruby" ]
    })
    create(:post, metadata: {
      "title" => "Python Post",
      "status" => "published",
      "date" => "2024-01-02",
      "tags" => [ "python" ]
    })

    content = <<~MARKDOWN
      ```collection
      heading: Ruby Only
      tags: ruby
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Ruby Post/, result)
    refute_match(/Python Post/, result)
  end

  test "collection filters by post_type" do
    create(:post, metadata: {
      "title" => "Article",
      "status" => "published",
      "date" => "2024-01-01",
      "post_type" => "article"
    })
    create(:post, metadata: {
      "title" => "Music",
      "status" => "published",
      "date" => "2024-01-02",
      "post_type" => "music"
    })

    content = <<~MARKDOWN
      ```collection
      heading: Articles
      post_type: article
      ```
    MARKDOWN

    result = render(content)

    assert_match(/Article/, result)
    refute_match(/Music/, result)
  end

  test "collection orders by date" do
    create(:post, metadata: {
      "title" => "Older",
      "status" => "published",
      "date" => "2024-01-01"
    })
    create(:post, metadata: {
      "title" => "Newer",
      "status" => "published",
      "date" => "2024-12-31"
    })

    content = <<~MARKDOWN
      ```collection
      heading: By Date
      order: date
      ```
    MARKDOWN

    result = render(content)

    newer_pos = result.index("Newer")
    older_pos = result.index("Older")
    assert newer_pos < older_pos, "Newer should appear before Older"
  end

  test "collection orders by title" do
    create(:post, metadata: {
      "title" => "Zebra Post",
      "status" => "published",
      "date" => "2024-01-01"
    })
    create(:post, metadata: {
      "title" => "Apple Post",
      "status" => "published",
      "date" => "2024-01-02"
    })

    content = <<~MARKDOWN
      ```collection
      heading: A-Z
      order: title
      ```
    MARKDOWN

    result = render(content)

    apple_pos = result.index("Apple Post")
    zebra_pos = result.index("Zebra Post")
    assert apple_pos < zebra_pos, "Apple should appear before Zebra"
  end

  test "collection show_more link" do
    # Create posts to have something to show
    3.times do |i|
      create(:post, metadata: {
        "title" => "Post #{i}",
        "status" => "published",
        "date" => "2024-01-0#{i+1}"
      })
    end

    content = <<~MARKDOWN
      ```collection
      heading: Featured
      limit: 1
      show_more: true
      show_more_text: "View all articles"
      ```
    MARKDOWN

    result = render(content)

    assert_match(/View all articles/, result)
  end

  # =============================================================================
  # Collection Grid Tests
  # =============================================================================

  test "consecutive collections grouped" do
    post1 = create(:post, metadata: { "title" => "Post 1", "status" => "published", "date" => "2024-01-01" })
    post2 = create(:post, metadata: { "title" => "Post 2", "status" => "published", "date" => "2024-01-02" })
    post3 = create(:post, metadata: { "title" => "Post 3", "status" => "published", "date" => "2024-01-03" })

    content = <<~MARKDOWN
      ```collection
      heading: First
      limit: 1
      ```

      ```collection
      heading: Second
      limit: 1
      ```
    MARKDOWN

    result = render(content)

    assert_match(/First/, result)
    assert_match(/Second/, result)
  end

  # =============================================================================
  # Edge Cases
  # =============================================================================

  test "handles empty card blocks" do
    content = <<~MARKDOWN
      ```card
      ```
    MARKDOWN

    result = render(content)

    assert result.present?
  end

  test "handles empty collection blocks" do
    content = <<~MARKDOWN
      ```collection
      ```
    MARKDOWN

    result = render(content)

    assert result.present?
  end

  test "handles empty gallery blocks" do
    content = <<~MARKDOWN
      ```gallery
      ```
    MARKDOWN

    # Empty galleries return empty or whitespace-only string in production
    result = render(content)
    assert result.blank?, "Expected empty gallery to return blank result, got: #{result.inspect}"

    # Empty galleries return HTML comment in preview mode
    result_preview = render(content, preview: true)
    assert_match(/<!-- Empty gallery -->/, result_preview)
  end

  test "unknown card type returns empty in production" do
    content = <<~MARKDOWN
      ```card
      type: unknown
      text: "Something"
      ```
    MARKDOWN

    result = render(content)

    assert result.blank?
  end

  # =============================================================================
  # Media embed tests (Obsidian-style `![](file.mp3|mp4)`)
  # =============================================================================

  test "audio file embed renders a native audio player" do
    result = render("![Episode 1](/media/audio/audio-abc.mp3)")

    assert_match(%r{<audio[^>]*controls}, result)
    assert_match(%r{src="/media/audio/audio-abc\.mp3"}, result)
    assert_match(/aria-label="Episode 1"/, result)
    refute_match(/<img/, result)
  end

  test "video file embed renders a native video player" do
    result = render("![Clip](/media/video/clip.mp4)")

    assert_match(%r{<video[^>]*controls}, result)
    assert_match(%r{src="/media/video/clip\.mp4"}, result)
    refute_match(/<img/, result)
  end

  test "audio embed without alt omits aria-label but still plays" do
    result = render("![](/media/audio/audio-xyz.m4a)")

    assert_match(%r{<audio[^>]*controls}, result)
    refute_match(/aria-label=/, result)
  end

  test "image embeds are unaffected by media embed handling" do
    result = render("![A photo](/media/images/pic.jpg)")

    refute_match(/<audio/, result)
    refute_match(/<video/, result)
  end

  # =============================================================================
  # Search triggers (```search block + collection search: true)
  # =============================================================================

  test "search block renders a scoped search trigger with sources and tags" do
    result = render("```search\nscope: documentation/products\ntags: ruby, -news\n```")

    assert_match(/class="site-search-trigger"/, result)
    assert_match(/data-search-trigger-scope-value=/, result)
    assert_match(/documentation/, result)
    assert_match(/products/, result)
    assert_match(/tagsInclude/, result)
    assert_match(/tagsExclude/, result)
  end

  test "search block treats a non-directory token as a post type" do
    result = render("```search\nscope: podcast\n```")

    assert_match(/data-search-trigger-scope-value=/, result)
    assert_match(/postTypes/, result)
    assert_match(/podcast/, result)
  end

  test "collection with search true renders the trigger inside a collection header" do
    result = render("```collection\nsource: documentation\nsearch: true\n```")

    assert_match(%r{<div class="collection-header">.*site-search-trigger}m, result)
    assert_match(/documentation/, result)
  end

  test "collection without search does not render a trigger" do
    result = render("```collection\nsource: documentation\n```")

    refute_match(/site-search-trigger/, result)
  end

  test "basic markdown still processed" do
    content = <<~MARKDOWN
      # Header

      Paragraph with **bold** text.
    MARKDOWN

    result = render(content)

    # Headers get auto-generated IDs
    assert_match(/<h1 id="header">Header<\/h1>/, result)
    assert_match(/<strong>bold<\/strong>/, result)
  end

  # =============================================================================
  # Roe-anji for / type selector (button + form)
  # =============================================================================

  def kind(config, **opts)
    TestModel.new("").send(:roeanji_kind, config, **opts)
  end

  def conflict_warning(config)
    TestModel.new("").send(:roeanji_kind_conflict_warning, config)
  end

  def in_dev_env
    original = Rails.env.to_s
    Rails.env = "development"
    yield
  ensure
    Rails.env = original
  end

  test "roeanji_kind reads `for`" do
    assert_equal "share", kind({ "for" => "share" })
  end

  test "roeanji_kind reads `type` as an alias" do
    assert_equal "signup", kind({ "type" => "signup" })
  end

  test "roeanji_kind: `for` wins when both are present" do
    assert_equal "share", kind({ "for" => "share", "type" => "product" })
  end

  test "roeanji_kind falls back to the default only when neither is set" do
    assert_equal "product", kind({}, default: "product")
    assert_nil kind({})
  end

  test "conflict warning is empty unless for and type disagree" do
    assert_equal "", conflict_warning({ "for" => "share" })
    assert_equal "", conflict_warning({ "type" => "share" })
    assert_equal "", conflict_warning({ "for" => "share", "type" => "share" })
    assert_equal "", conflict_warning({})
  end

  test "conflict warning fires (in dev) when for and type disagree" do
    in_dev_env do
      html = conflict_warning({ "for" => "share", "type" => "product" })
      assert_includes html, "Conflicting selector"
      # `for` is rendered as inline <code> in dev warnings now.
      assert_includes html, "for</code> wins"
    end
  end

  test "an unknown non-product button dev-warns in dev, silent otherwise" do
    button = { kind: "mystery", config: {} }
    assert_equal "", TestModel.new("").send(:render_action_button, button, {}), "silent outside dev"

    in_dev_env do
      html = TestModel.new("").send(:render_action_button, button, {})
      assert_includes html, "Unknown button type"
      assert_includes html, "mystery"
    end
  end

  # ---- share button ----------------------------------------------------------

  test "render_share_button emits a Share trigger + copy/email menu" do
    html = TestModel.new("").send(:render_share_button, {}, {})
    assert_includes html, 'data-controller="share"'
    assert_includes html, 'data-share-target="trigger"'
    assert_includes html, 'data-action="share#toggle"'
    assert_includes html, 'data-share-target="menu"'
    assert_includes html, 'data-action="share#copy"'
    assert_includes html, 'href="mailto:"'
    assert_includes html, ">Share</button>"   # default trigger label
    assert_includes html, ">Copy link</button>"
  end

  test "share button honours label + url/title/text config" do
    html = TestModel.new("").send(:render_share_button,
      { "label" => "Send it", "url" => "/x", "title" => "T", "text" => "msg" }, {})
    assert_includes html, ">Send it</button>"
    assert_includes html, 'data-share-url-value="/x"'
    assert_includes html, 'data-share-title-value="T"'
    assert_includes html, 'data-share-text-value="msg"'
  end

  test "`for: share` routes through the pipeline to the share button" do
    html = render("```button\nfor: share\n```")
    assert_includes html, 'data-controller="share"'
    assert_includes html, "share#copy"
  end

  test "`type: share` is an alias for `for: share`" do
    html = render("```button\ntype: share\n```")
    assert_includes html, 'data-controller="share"'
  end

  # ---- members (subscribe) button --------------------------------------------

  def with_members_enabled(enabled = true)
    sc = SiteFeature.singleton_class
    sc.send(:alias_method, :__orig_members_enabled?, :members_enabled?)
    sc.send(:define_method, :members_enabled?) { enabled }
    yield
  ensure
    sc.send(:alias_method, :members_enabled?, :__orig_members_enabled?)
    sc.send(:remove_method, :__orig_members_enabled?)
  end

  test "members button links to /sign-up with a Subscribe label" do
    with_members_enabled do
      html = TestModel.new("").send(:render_members_button, {}, {})
      assert_includes html, '<a class="btn-primary" href="/sign-up">Subscribe</a>'
    end
  end

  test "members button honours label / url / style" do
    with_members_enabled do
      html = TestModel.new("").send(:render_members_button,
        { "label" => "Join", "url" => "/upgrade", "style" => "small" }, {})
      assert_includes html, ">Join</a>"
      assert_includes html, 'href="/upgrade"'
      assert_includes html, 'class="btn-primary members-small"'
    end
  end

  test "members button dev-warns in dev, silent otherwise, when members are off" do
    with_members_enabled(false) do
      assert_equal "", TestModel.new("").send(:render_members_button, {}, {}), "silent outside dev"
      in_dev_env do
        html = TestModel.new("").send(:render_members_button, {}, {})
        assert_includes html, "Subscribe button unavailable"
      end
    end
  end

  test "`for: subscribe` (and `type: subscribe`) route to the members button" do
    with_members_enabled do
      assert_includes render("```button\nfor: subscribe\n```"), 'href="/sign-up"'
      assert_includes render("```button\ntype: subscribe\n```"), 'href="/sign-up"'
    end
  end

  test "share button carries the stable .share hook + omits empty values" do
    html = TestModel.new("").send(:render_share_button, {}, {})
    assert_includes html, '<div class="share" data-controller="share">'
    refute_includes html, "data-share-url-value"
  end

  test "share menu uses the reusable .button-menu hook" do
    html = TestModel.new("").send(:render_share_button, {}, {})
    assert_includes html, '<div class="button-menu" data-share-target="menu">'
  end

  test "share button `style:` adds sanitised modifier classes after the base" do
    html = TestModel.new("").send(:render_share_button, { "style" => "small center" }, {})
    assert_includes html, '<div class="share share-small share-center" data-controller="share"'
  end

  test "share button `style:` strips unsafe characters" do
    html = TestModel.new("").send(:render_share_button, { "style" => "sm<all>" }, {})
    assert_includes html, 'class="share share-small"'
  end
end
