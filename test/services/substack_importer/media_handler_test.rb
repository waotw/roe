# frozen_string_literal: true

require "test_helper"

module SubstackImporter
  class MediaHandlerTest < ActiveSupport::TestCase
    # Lightweight stand-in for the file-backed Post the handler reads from.
    PostDouble = Struct.new(
      :id, :slug, :html_content, :cover_image, :podcast_url, :video_mux_playback_id,
      keyword_init: true
    )

    def setup
      @tmp_dir = Dir.mktmpdir("media_handler_test")
      @post = PostDouble.new(
        id: 1,
        slug: "my-post",
        html_content: %(<p>Hello</p><img src="https://cdn.substack.com/image/pic.jpg" alt="pic">),
        cover_image: "https://cdn.substack.com/image/cover.png",
        podcast_url: "https://cdn.substack.com/audio/ep.mp3",
        video_mux_playback_id: "abc123"
      )
    end

    def teardown
      FileUtils.rm_rf(@tmp_dir)
    end

    def test_ignore_media_writes_expected_local_paths_without_downloading
      handler = MediaHandler.new(site_root: @tmp_dir, ignore_media: true)

      local_media = handler.download_post_media(@post)

      # Returned paths point at the expected local locations...
      assert_equal [ "/media/images/my-post-1.jpg" ], local_media[:images]
      assert_equal "/media/images/my-post-cover.png", local_media[:cover_image]
      assert_equal "/media/audio/my-post.mp3", local_media[:audio]
      assert_equal "/media/video/my-post.mp4", local_media[:video]

      # ...but nothing is flagged as missing (a missing entry would drive a warning).
      assert_empty local_media[:missing]

      # No files were written to disk and no Medium rows were created.
      assert_empty Dir.glob(File.join(@tmp_dir, "media", "**", "*")).select { |p| File.file?(p) }
      assert_equal 0, Medium.count

      # The URL mappings let replace_urls rewrite the body to local paths, so a
      # re-run with the option off backfills the real files into these paths.
      rewritten = handler.replace_urls(@post.html_content)
      assert_includes rewritten, "/media/images/my-post-1.jpg"
      refute_includes rewritten, "https://cdn.substack.com/image/pic.jpg"
    end
  end
end
