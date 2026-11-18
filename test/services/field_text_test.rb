require "test_helper"

class FieldTextTest < ActiveSupport::TestCase
  test "bold, italic, links and code render inline, with no wrapping paragraph" do
    html = FieldText.html("A review of *Moby Dick*, **twice**, [here](/x) and `code`")
    assert_includes html, "<em>Moby Dick</em>"
    assert_includes html, "<strong>twice</strong>"
    assert_includes html, %(<a href="/x">here</a>)
    assert_includes html, "<code>code</code>"
    assert_not_includes html, "<p>"
    assert html.html_safe?
  end

  test "a line break is a <br>, and the value stays one run of text" do
    html = FieldText.html("_the quote_\n— benjamin welch")
    assert_equal "<em>the quote</em><br>\n— benjamin welch", html
  end

  test "Windows line endings and blank lines don't add paragraphs" do
    html = FieldText.html("First line\r\n\r\nSecond line")
    assert_equal "First line<br>\nSecond line", html
  end

  test "a line can't start a list, heading, quote or rule" do
    { "- benjamin welch" => "- benjamin welch", "# Not a heading" => "# Not a heading",
      "> not a quote" => "> not a quote", "1. not a list" => "1. not a list" }.each do |source, text|
      html = FieldText.html("_quote_\n#{source}")
      assert_not_includes html, "<li>", source
      assert_not_includes html, "<h1", source
      assert_not_includes html, "<blockquote>", source
      assert_includes Nokogiri::HTML.fragment(html).text, text, source
    end
  end

  test "plain values come through as written" do
    assert_equal "https://example.com/some_file_name.pdf", FieldText.plain("https://example.com/some_file_name.pdf")
    assert_equal "my_custom_value", FieldText.plain("my_custom_value")
    assert_equal "42", FieldText.plain(42)
    assert_equal "a, b", FieldText.plain(%w[a b])
  end

  test "typography follows the body" do
    assert_equal "I\u2019m here\u2026", FieldText.plain("I'm here...")
  end

  test "text is escaped where it isn't markup" do
    assert_includes FieldText.html("Tom & Jerry"), "Tom &amp; Jerry"
  end

  test "plain takes the Markdown out and joins lines" do
    assert_equal "the quote — benjamin", FieldText.plain("_the quote_\n— benjamin")
    assert_equal "the quote\n— benjamin", FieldText.plain("_the quote_\n— benjamin", separator: "\n")
    assert_equal "Moby Dick & more", FieldText.plain("*Moby Dick* & more")
  end

  test "nothing to show is empty" do
    assert_equal "", FieldText.html(nil)
    assert_equal "", FieldText.html("  \n ")
    assert_equal "", FieldText.plain(nil)
  end

  test "a value that fits keeps its Markdown; a long one is cut as plain text" do
    assert_equal "*short*", FieldText.shortened("*short*", 20)

    cut = FieldText.shortened("A *long* value about Tom & Jerry", 12)
    assert cut.html_safe?
    assert_equal "A long val...", CGI.unescapeHTML(cut.to_str)
    assert_equal cut, FieldText.html(cut)
    assert_includes FieldText.html(FieldText.shortened("Tom & Jerry and more", 10)), "&amp;"
  end
end
