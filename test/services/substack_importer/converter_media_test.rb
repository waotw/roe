# frozen_string_literal: true

require "test_helper"

module SubstackImporter
  class ConverterMediaTest < ActiveSupport::TestCase
    # --- Audio embeds --------------------------------------------------------

    AUDIO_HTML = %(<div class="native-audio-embed" data-component-name="AudioPlaceholder" ) +
                 %(data-attrs="{&quot;label&quot;:null,&quot;mediaUploadId&quot;:&quot;34fd1f0e-b9f1-4ee8-a994-b5e8bf86af35&quot;,) +
                 %(&quot;duration&quot;:24.346,&quot;downloadable&quot;:false}"></div>)

    def test_audio_embed_emits_local_media_embed
      converter = Converter.new
      md = converter.convert(AUDIO_HTML)

      assert_includes md, "![Audio](/media/audio/audio-34fd1f0e-b9f1-4ee8-a994-b5e8bf86af35.mp3)"
      refute_includes md, "[AUDIO:"
    end

    def test_audio_embed_is_collected_for_download
      converter = Converter.new
      converter.convert(AUDIO_HTML)

      assert_equal 1, converter.collected_audio.size
      embed = converter.collected_audio.first
      assert_equal "34fd1f0e-b9f1-4ee8-a994-b5e8bf86af35", embed[:media_id]
      assert_equal "audio-34fd1f0e-b9f1-4ee8-a994-b5e8bf86af35.mp3", embed[:filename]
    end

    # --- Share buttons -------------------------------------------------------

    def share_card?(md)
      md.include?("```card") && md.include?("type: share")
    end

    def test_share_button_from_export_wrapper_becomes_card
      html = %(<p class="button-wrapper" data-component-name="ButtonCreateButton" ) +
             %(data-attrs="{&quot;url&quot;:&quot;https://foo.substack.com/p/my-post?utm_source=substack&amp;action=share&quot;,) +
             %(&quot;text&quot;:&quot;Share&quot;}"><a class="button primary" href="#"><span>Share</span></a></p>)

      md = Converter.new(substack_url: "foo.substack.com").convert(html)

      assert share_card?(md), "expected a share card, got: #{md}"
      assert_includes md, "link: /posts/my-post"
      refute_includes md, "[BUTTON:"
      refute_includes md, "action=share"
    end

    def test_share_button_from_livefetch_anchor_becomes_card
      # Live-fetch renders the share button as a bare styled anchor, no wrapper.
      html = %(<p><a class="button primary" ) +
             %(href="https://foo.substack.com/p/my-post?utm_source=substack&amp;action=share"><span>Share</span></a></p>)

      md = Converter.new(substack_url: "foo.substack.com").convert(html)

      assert share_card?(md), "expected a share card, got: #{md}"
      assert_includes md, "link: /posts/my-post"
      refute_includes md, "action=share"
    end

    def test_non_share_button_is_unchanged
      html = %(<p class="button-wrapper" data-component-name="ButtonCreateButton" ) +
             %(data-attrs="{&quot;url&quot;:&quot;https://example.com/thing&quot;,&quot;text&quot;:&quot;Read more&quot;}">) +
             %(<a class="button" href="#">Read more</a></p>)

      md = Converter.new(substack_url: "foo.substack.com").convert(html)

      refute share_card?(md)
      assert_includes md, "[BUTTON: Read more]"
    end

    def test_ordinary_link_not_treated_as_share
      # An ordinary content link (no button class) with a stray action=share
      # in an external URL should stay a normal link, not become a card.
      html = %(<p><a href="https://example.com/x?action=share">read this</a></p>)

      md = Converter.new(substack_url: "foo.substack.com").convert(html)

      refute share_card?(md)
      assert_includes md, "[read this]"
    end
  end
end
