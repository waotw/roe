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

  test "auto_numbers footnotes sequentially" do
    content = "First statement(*First footnote*). Second statement(*Second footnote*)."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_match(/\[\^1\]: First footnote/, result)
    assert_match(/\[\^2\]: Second footnote/, result)
    assert_match(/\[\^1\]/, result)
    assert_match(/\[\^2\]/, result)
  end

  test "custom marker with bracket syntax" do
    content = "According to research(*[source] Scientific Journal*), this is true."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_match(/\[\^source\]: Scientific Journal/, result)
    assert_match(/\[\^source\]/, result)
  end

  test "multiple footnotes appended at end" do
    content = "One(*First*). Two(*Second*). Three(*Third*)."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_match(/\[\^1\]: First/, result)
    assert_match(/\[\^2\]: Second/, result)
    assert_match(/\[\^3\]: Third/, result)
    
    footnote_section = result.split("1]: First").last
    assert_match(/2\]: Second/, footnote_section)
    assert_match(/3\]: Third/, footnote_section)
  end

  test "no footnotes unchanged" do
    content = "This is plain text without any footnotes."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_equal content, result
  end

  test "text without parentheses unchanged" do
    content = "# Hello World\n\nThis is normal (parentheses) text."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_equal content, result
  end

  test "handles nested parentheses in footnote" do
    content = "Statement(*Footnote with (nested) content*)."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_match(/\[\^1\]: Footnote with \(nested\) content/, result)
  end

  test "single footnote returns correct numbering" do
    content = "Just one(*Solo footnote*)."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_match(/\[\^1\]: Solo footnote/, result)
    refute_match(/\[\^2\]/, result)
  end

  test "mixed auto and custom markers" do
    content = "Auto(*Auto one*). Custom(*[cite] Citation*). Auto(*Auto two*)."
    model = TestModel.new(content)
    
    result = model.to_html
    
    assert_match(/\[\^1\]: Auto one/, result)
    assert_match(/\[\^cite\]: Citation/, result)
    assert_match(/\[\^2\]: Auto two/, result)
  end
end
