# frozen_string_literal: true

require "test_helper"

module SubstackImporter
  class ConverterLinkTest < ActiveSupport::TestCase
    LINK = %(<p>See <a href="https://foo.substack.com/p/my-post">my post</a>.</p>)

    def test_rewrites_internal_link_with_schemed_base_url
      md = Converter.new(substack_url: "https://foo.substack.com").convert(LINK)
      assert_includes md, "(/posts/my-post)"
      refute_includes md, "foo.substack.com"
    end

    def test_rewrites_internal_link_with_schemeless_base_url
      # Regression: a base URL entered without a scheme used to leave .host
      # nil and silently disable all internal-link rewriting.
      md = Converter.new(substack_url: "foo.substack.com").convert(LINK)
      assert_includes md, "(/posts/my-post)"
      refute_includes md, "foo.substack.com"
    end

    def test_rewrites_top_level_page_to_relative_path
      # Top-level Substack pages (/about, /archive) aren't under /p/ — they
      # should become root-relative paths that resolve on the Roe site.
      md = Converter.new(substack_url: "foo.substack.com").convert(
        %(<p><a href="https://foo.substack.com/about">about</a></p>)
      )
      assert_includes md, "(/about)"
      refute_includes md, "foo.substack.com"
    end

    def test_leaves_other_publications_alone
      md = Converter.new(substack_url: "foo.substack.com").convert(
        %(<p><a href="https://other.substack.com/p/theirs">theirs</a></p>)
      )
      assert_includes md, "https://other.substack.com/p/theirs"
    end

    def test_no_base_url_leaves_links_untouched
      md = Converter.new.convert(LINK)
      assert_includes md, "https://foo.substack.com/p/my-post"
    end
  end
end
