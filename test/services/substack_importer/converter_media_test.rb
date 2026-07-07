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

    # --- Image galleries -----------------------------------------------------

    def gallery_html(caption:)
      cap = caption.nil? ? "null" : %("#{caption}")
      attrs = %({&quot;gallery&quot;:{&quot;images&quot;:[) +
              %({&quot;src&quot;:&quot;https://x/a.jpg&quot;,&quot;alt&quot;:&quot;a&quot;},) +
              %({&quot;src&quot;:&quot;https://x/b.jpg&quot;,&quot;alt&quot;:&quot;b&quot;}],) +
              %(&quot;caption&quot;:#{cap.gsub('"', "&quot;")}}})
      %(<div class="image-gallery-embed" data-attrs="#{attrs}"></div>)
    end

    # N images with src/alt = 1..N, optional gallery caption.
    def gallery_html_n(count, caption: nil)
      imgs = (1..count).map do |i|
        %({&quot;src&quot;:&quot;https://x/#{i}.jpg&quot;,&quot;alt&quot;:&quot;#{i}&quot;})
      end.join(",")
      cap = caption.nil? ? "null" : %("#{caption}").gsub('"', "&quot;")
      attrs = %({&quot;gallery&quot;:{&quot;images&quot;:[#{imgs}],&quot;caption&quot;:#{cap}}})
      %(<div class="image-gallery-embed" data-attrs="#{attrs}"></div>)
    end

    def test_four_image_gallery_splits_into_two_by_two_rows
      md = Converter.new.convert(gallery_html_n(4))

      assert_includes md, "```gallery", "row split requires an explicit fence"
      # Row 1 = images 1,2 on adjacent lines; blank line; row 2 = images 3,4.
      assert_includes md, "![1](https://x/1.jpg)\n![2](https://x/2.jpg)"
      assert_includes md, "![2](https://x/2.jpg)\n\n![3](https://x/3.jpg)"
      assert_includes md, "![3](https://x/3.jpg)\n![4](https://x/4.jpg)"
    end

    def test_four_image_gallery_keeps_caption_with_the_grid
      md = Converter.new.convert(gallery_html_n(4, caption: "Weekend away"))

      assert_includes md, "```gallery"
      assert_includes md, "![2](https://x/2.jpg)\n\n![3](https://x/3.jpg)"
      assert_includes md, "caption: Weekend away"
    end

    def test_six_image_gallery_stays_a_simple_single_run
      md = Converter.new.convert(gallery_html_n(6))

      refute_includes md, "```gallery", "6 images ⇒ default 3×2, no forced rows"
      (1..6).each { |i| assert_includes md, "![#{i}](https://x/#{i}.jpg)" }
      refute_includes md, "\n\n![", "no blank-line row break in a simple run"
    end

    def test_gallery_caption_becomes_fenced_gallery_directive
      md = Converter.new.convert(gallery_html(caption: "A day on the moor"))

      assert_includes md, "```gallery"
      assert_includes md, "![a](https://x/a.jpg)"
      assert_includes md, "![b](https://x/b.jpg)"
      assert_includes md, "caption: A day on the moor"
      # The caption must no longer be hung off the first image.
      refute_includes md, "(*A day on the moor*)"
    end

    def test_gallery_without_caption_emits_bare_image_lines
      md = Converter.new.convert(gallery_html(caption: nil))

      assert_includes md, "![a](https://x/a.jpg)"
      assert_includes md, "![b](https://x/b.jpg)"
      refute_includes md, "```gallery", "no caption ⇒ rely on auto-gallery grouping"
      refute_includes md, "caption:"
    end

    def test_gallery_images_are_collected_for_download
      converter = Converter.new
      converter.convert(gallery_html(caption: "cap"))

      srcs = converter.collected_images.map { |i| i[:src] }
      assert_includes srcs, "https://x/a.jpg"
      assert_includes srcs, "https://x/b.jpg"
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
