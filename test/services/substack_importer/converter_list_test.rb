# frozen_string_literal: true

require "test_helper"

module SubstackImporter
  class ConverterListTest < ActiveSupport::TestCase
    # A block child of a list item must be indented by the marker width so it
    # stays part of the item instead of terminating the list. Regression: at
    # column 0 the blockquote broke out and swallowed the next item.
    def test_blockquote_inside_list_item_is_indented
      html = %(<ul><li><p>Item one.</p></li>) +
             %(<li><p>Item two:</p><blockquote><p>Quoted line.</p></blockquote></li>) +
             %(<li><p>Item three.</p></li></ul>)

      md = Converter.new.convert(html)

      assert_includes md, "- Item two:\n\n  > Quoted line."
      assert_includes md, "- Item three."
    end

    def test_ordered_list_indents_by_three_for_number_marker
      html = %(<ol><li><p>First:</p><blockquote><p>quote</p></blockquote></li>) +
             %(<li><p>Second</p></li></ol>)

      md = Converter.new.convert(html)

      assert_includes md, "1. First:\n\n   > quote"
      assert_includes md, "2. Second"
    end

    def test_nested_list_is_indented
      html = %(<ul><li><p>Parent</p><ul><li><p>Child A</p></li><li><p>Child B</p></li></ul></li>) +
             %(<li><p>Sibling</p></li></ul>)

      md = Converter.new.convert(html)

      assert_includes md, "- Parent\n\n  - Child A\n  - Child B"
    end

    def test_multi_paragraph_item_keeps_second_paragraph_indented
      html = %(<ul><li><p>Para one.</p><p>Para two.</p></li><li><p>Next.</p></li></ul>)

      md = Converter.new.convert(html)

      assert_includes md, "- Para one.\n\n  Para two."
    end

    def test_simple_flat_list_is_unchanged
      html = %(<ul><li><p>One</p></li><li><p>Two</p></li></ul>)

      md = Converter.new.convert(html)

      assert_equal "- One\n- Two", md.strip
    end
  end
end
