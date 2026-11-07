require "test_helper"

# The live help beside the layout editor: an HTML example built from the
# layout's own reading, and a description of every line and box.
class ContentLayoutExplainTest < ActiveSupport::TestCase
  ARTICLE = <<~TEXT
    post-header:
    post-header-top: [title] [feed links]
    [subtitle]
    post-meta: [date] [author]
    [image]

    [body]
  TEXT

  def explain(text, name = "article") = ContentLayout::Explain.new(name, text).as_json

  def markup(result) = result[:html].map { |e| ("  " * e[:depth]) + e[:text] }.join("\n")

  test "the HTML example nests the layout inside the show page's wrapper" do
    assert_equal <<~HTML.strip, markup(explain(ARTICLE))
      <article class="post post-article">
        <div class="content">
          <header class="post-header">
            <div class="post-header-top">
              <h1 class="post-title">Title</h1>
              <div class="feed-links"><a class="feed-link">RSS</a></div>
            </div>
            <p class="post-subtitle">Subtitle</p>
            <div class="post-meta">
              <time class="post-date">March 5, 2026</time>
              <span class="post-author">Author</span>
            </div>
            <img class="post-image">
          </header>
          <div class="post-content">…the post's writing…</div>
        </div>
      </article>
    HTML
  end

  test "each example line knows the source line that drew it" do
    entries = explain(ARTICLE)[:html]
    assert_equal 1, entries.find { |e| e[:text] == %(<header class="post-header">) }[:line]
    assert_equal 4, entries.find { |e| e[:text].include?("post-date") }[:line]
    assert_nil entries.first[:block], "the show page's wrapper belongs to no block"
  end

  test "a block's name line explains the block and where its role comes from" do
    help = explain(ARTICLE)[:lines]["1"]
    assert_includes help[:text], "[title] to [image]"
    assert_includes help[:text], "`<header>` with the class `post-header`"
    assert_equal 0, help[:block]
  end

  test "a group says which side of the body it's on" do
    lines = explain("[title]\n\n[date]\n\n[body]\n\n[author]\n\n[subtitle]\n")[:lines]
    assert_match(/between the header and the body\.\z/, lines["3"][:text])
    assert_match(/between the body and the footer\.\z/, lines["7"][:text])
  end

  test "quotes are curly in the help, but not inside code" do
    help = explain("[subtitle] [date]\n[body]\n")[:lines]["1"][:text]
    assert_includes help, "It’s with the writing."
    assert_includes help, '`<div class="layout-row">`'
    refute_includes help.gsub(/`[^`]*`/, ""), "'"
  end

  test "a named row is explained, and each box has its own description and columns" do
    help = explain(ARTICLE)[:lines]["2"]
    assert_includes help[:text], "[title] and [feed links]"
    assert_includes help[:text], "`post-header-top`"
    assert help[:text].end_with?("It’s in the header.")
    title = help[:boxes].first
    assert_equal [ 17, 24 ], [ title[:from], title[:to] ]
    assert_equal "The post’s title, from `title:`.", title[:text]
  end

  test "[body] says whose writing it is" do
    assert_match(/\AThe post’s writing/, explain(ARTICLE)[:lines]["7"][:boxes].first[:text])
    assert_match(/\AThe product’s writing/, explain("[body]\n", "product")[:lines]["1"][:boxes].first[:text])
    assert_match(/\AThe documentation page’s writing/, explain("[body]\n", "documentation")[:lines]["1"][:boxes].first[:text])
  end

  test "blank lines, problems and fields are explained" do
    lines = explain("[title]\n\nnot a box\n[location]\n[body]\n")[:lines]
    assert_match(/empty line ends one block/, lines["2"][:text])
    assert lines["3"][:problem]
    assert_match(/Line 3 isn’t a row of \[boxes\]/, lines["3"][:text])
    assert_match(/`location:` field/, lines["4"][:text])
  end

  test "warnings come with the example" do
    assert_match(/no \[body\]/, explain("[title]\n")[:warnings].join)
  end

  test "an unnamed body block draws no wrapper; a named one does" do
    refute_includes markup(explain("[player]\n[body]\n", "audio")), "layout-group"
    assert_includes markup(explain("story:\n[player]\n[body]\n", "audio")), %(<div class="story">)
  end
end
