require "test_helper"

class PunctuationSpacesTest < ActiveSupport::TestCase
  NBSP = "\u00A0"

  def apply(html) = PunctuationSpaces.apply(html)

  test "the space before ? ! : ; and » can't break" do
    assert_equal "<p>D’immigrés#{NBSP}? Oui#{NBSP}! Da#{NBSP}: non#{NBSP}; « bon#{NBSP}»</p>".sub("« ", "«#{NBSP}"),
                 apply("<p>D’immigrés ? Oui ! Da : non ; « bon »</p>")
  end

  test "the space after « can't break, and kramdown's entities count" do
    assert_equal "&laquo;#{NBSP}oui#{NBSP}&raquo;", apply("&laquo; oui &raquo;")
  end

  test "a space after a tag counts, as in a name in bold" do
    assert_equal "<strong>Da</strong>#{NBSP}: Oui", apply("<strong>Da</strong> : Oui")
  end

  test "English without spaces before the marks is unchanged" do
    text = "<p>Is it? Yes! Note: this; that. Visit <a href=\"https://x.test/a?b=1\">here</a>.</p>"
    assert_equal text, apply(text)
  end

  test "attributes, code and preformatted text are left alone" do
    html = %(<a title="pourquoi ?" href="/x">x</a> <code>a ? b : c</code><pre><code>if a ? b : c</code></pre>)
    assert_equal html, apply(html)
  end

  test "text after a code element is still changed" do
    assert_equal "<code>a ? b</code> et alors#{NBSP}?", apply("<code>a ? b</code> et alors ?")
  end

  test "keeps an HTML-safe string HTML-safe" do
    assert apply("<p>oui ?</p>".html_safe).html_safe?
  end

  test "a post body renders with it" do
    html = Post.new(content: "L’homme : D’immigrés ?\n\n```\nx ? y : z\n```\n").to_html
    assert_includes html, "L’homme#{NBSP}: D’immigrés#{NBSP}?"
    assert_includes html, "x ? y : z", "code untouched"
  end

  test "metadata fields render with it, but their plain text keeps ordinary spaces" do
    assert_includes FieldText.html("Vraiment ?"), "Vraiment#{NBSP}?"
    assert_equal "Vraiment ?", FieldText.plain("Vraiment ?")
  end
end
