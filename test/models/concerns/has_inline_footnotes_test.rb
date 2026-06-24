require "test_helper"

class HasInlineFootnotesTest < ActiveSupport::TestCase
  class TestModel
    include HasInlineFootnotes

    attr_reader :content

    def initialize(content)
      @content = content
    end

    def to_html
      process_inline_footnotes(@content)
    end
  end

  test "text without footnotes passes through unchanged" do
    content = "This is plain text without any footnotes."
    model = TestModel.new(content)

    result = model.to_html

    assert_equal content, result
  end

  test "text with parentheses passes through unchanged" do
    content = "# Hello World\n\nThis is normal (parentheses) text."
    model = TestModel.new(content)

    result = model.to_html

    assert_equal content, result
  end

  test "retired inline footnote syntax passes through unchanged" do
    content = "According to research(*[source] Scientific Journal*), this is true."
    model = TestModel.new(content)

    result = model.to_html

    assert_equal content, result
  end
end
