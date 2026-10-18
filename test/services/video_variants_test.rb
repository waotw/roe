require "test_helper"
require_relative "../video_test_helpers"

# Video web versions: what gets made, how it's served, and what stays
# protected. The encode tests run real ffmpeg on tiny generated clips and
# skip where ffmpeg isn't installed; everything else works from manifests
# written by hand, so it runs anywhere — the same way a live site without
# ffmpeg serves what Site Sync brought.
class VideoVariantGeneratorTest < ActiveSupport::TestCase
  include VideoTestHelpers
  include ActiveJob::TestHelper

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  test "never upscales: renditions at or below the source's shorter side" do
    assert_equal %w[720p], VideoVariantGenerator.rendition_names_for(480)
    assert_equal %w[720p], VideoVariantGenerator.rendition_names_for(720)
    assert_equal %w[720p], VideoVariantGenerator.rendition_names_for(900)
    assert_equal %w[720p 1080p], VideoVariantGenerator.rendition_names_for(1080)
    assert_equal %w[720p 1080p], VideoVariantGenerator.rendition_names_for(2160)
  end

  test "frame rate: up to 30 and 50/60 kept, slow-motion rates halved" do
    assert_nil VideoVariantGenerator.target_frame_rate(29.97)
    assert_nil VideoVariantGenerator.target_frame_rate(30)
    assert_nil VideoVariantGenerator.target_frame_rate(59.94)
    assert_nil VideoVariantGenerator.target_frame_rate(50)
    assert_equal 30.0, VideoVariantGenerator.target_frame_rate(120)
    assert_equal 30.0, VideoVariantGenerator.target_frame_rate(240)
  end

  test "variant names trace back to their original" do
    src = File.join(VIDEO_DIR, "clip.mov")
    assert_equal File.join(VIDEO_DIR, "variants", "clip-720p.mp4"), VideoVariantGenerator.variant_path_for(src, "720p")
    assert_equal File.join(VIDEO_DIR, "variants", "clip-poster.jpg"), VideoVariantGenerator.variant_path_for(src, "poster")
    assert_equal File.join(VIDEO_DIR, "variants", "clip-video.json"), VideoVariantGenerator.manifest_path(src)
  end

  test "a 360p clip gets a poster and a 720p rendition at its own size, small and web-ready" do
    web = make_clip("small.mp4", size: "640x360", bitrate: "3M")
    make_all(web)

    manifest = VideoVariantGenerator.current_manifest(web)
    assert manifest["complete"]
    assert_equal %w[720p], manifest["renditions"].map { |r| r["name"] }

    out = VideoVariantGenerator.variant_path_for(VideoVariantGenerator.normalize_path(web), "720p")
    probe = MediaProbe.call(out)
    assert_equal [ 640, 360 ], [ probe.width, probe.height ], "never upscaled"
    assert_equal "h264", probe.video_codec
    assert_equal "yuv420p", probe.pixel_format
    assert_operator File.size(out), :<, File.size(VideoVariantGenerator.normalize_path(web))

    head = File.binread(out, 4096)
    assert_operator head.index("moov").to_i, :<, head.index("mdat") || 4096, "faststart puts the index first"
    assert_equal "\xFF\xD8\xFF".b, File.binread(VideoVariantGenerator.variant_path_for(VideoVariantGenerator.normalize_path(web), "poster"), 3), "poster is a JPEG"
  end

  test "a vertical HDR phone clip comes out upright, 8-bit, SDR, without location data" do
    web = make_clip("phone.mov", size: "1920x1080", rotate: 90, hevc_10bit: true, rate: 60)
    make_all(web)

    source = VideoVariantGenerator.normalize_path(web)
    r720 = MediaProbe.call(VideoVariantGenerator.variant_path_for(source, "720p"))
    r1080 = MediaProbe.call(VideoVariantGenerator.variant_path_for(source, "1080p"))

    assert_equal [ 720, 1280 ], [ r720.width, r720.height ], "measured by the short side, upright"
    assert_equal [ 1080, 1920 ], [ r1080.width, r1080.height ]
    assert_equal 0, r720.rotation
    assert_equal "h264", r720.video_codec
    assert_equal "yuv420p", r720.pixel_format

    tags, = ManagedTools::Platform.run(ffmpeg_tool.ffprobe_path, "-v", "error", "-show_entries", "format_tags",
                                       "-of", "compact", VideoVariantGenerator.variant_path_for(source, "720p"), timeout: 20)
    assert_no_match(/location/, tags)
  end

  test "an already web-ready original that wouldn't shrink is served as it is" do
    web = make_clip("lean.mp4", size: "640x360", bitrate: "150k")
    make_all(web)

    manifest = VideoVariantGenerator.current_manifest(web)
    assert manifest["complete"]
    assert_equal [], manifest["renditions"]
    assert_equal %w[720p], manifest["skipped"]
    assert_equal [ web ], VideoRenderer.plan(web).sources.map { |s| s[:src] }
  end

  test "replacing the original makes the old web versions stale" do
    web = fake_variants("swap.mp4")
    assert VideoVariantGenerator.complete?(web)

    File.binwrite(VideoVariantGenerator.normalize_path(web), "y" * 2000)
    assert_not VideoVariantGenerator.complete?(web)
    assert_equal [], VideoVariantGenerator.available_renditions(web)
  end

  test "deleting a video's Medium removes its web versions" do
    web = fake_variants("gone.mp4")
    medium = Medium.create!(file_path: web, media_type: "video")
    source = VideoVariantGenerator.normalize_path(web)

    medium.destroy
    VideoVariantGenerator.all_variant_paths(source).each { |p| assert_not File.exist?(p), p }
  end

  test "prune_orphans! removes web versions whose original is gone, and nothing else" do
    keep = fake_variants("keep.mp4")
    lost = fake_variants("lost.mov")
    File.delete(VideoVariantGenerator.normalize_path(lost))

    assert_equal 3, VideoVariantGenerator.prune_orphans!
    assert File.exist?(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(keep)))
  end

  test "queue! does nothing without ffmpeg, and queues a poster plus each rendition with it" do
    web = fake_variants("q.mp4")
    File.delete(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(web)))

    VideoVariantGenerator.stubs(:available?).returns(false)
    assert_no_enqueued_jobs { assert_not VideoVariantGenerator.queue!(web) }

    VideoVariantGenerator.stubs(:available?).returns(true)
    Rails.cache.delete(VideoVariantGenerator.queue_cache_key(web))
    assert_enqueued_jobs 3, only: TranscodeVideoJob do
      assert VideoVariantGenerator.queue!(web)
    end
    assert_no_enqueued_jobs { assert_not VideoVariantGenerator.queue!(web) } # deduped
  ensure
    Rails.cache.delete(VideoVariantGenerator.queue_cache_key(web)) if web
  end

  test "refuses to work on a variant file" do
    VideoVariantGenerator.stubs(:available?).returns(true)
    assert_not VideoVariantGenerator.queue!("/media/video/variants/clip-720p.mp4")
  end

  test "a video still being copied in is retried, not failed" do
    web = make_clip("arriving.mp4", size: "640x360")
    path = VideoVariantGenerator.normalize_path(web)

    # Simulate a copy still writing: the file grows while the check watches.
    writer = Thread.new { 3.times { sleep 0.5; File.open(path, "ab") { |f| f.write("x" * 4096) } } }
    assert_raises(VideoVariantGenerator::StillArriving) { VideoVariantGenerator.generate(web, "poster") }
    writer.join
    assert_nil VideoVariantGenerator.read_manifest(web), "nothing made from a half-copied file"
  end

  # Your report: a fresh upload (modified "just now", but complete) was
  # treated as still arriving, so every job retried and the progress window
  # stopped watching. Only a growing file counts now.
  test "a just-finished upload isn't mistaken for a copy in progress" do
    web = make_clip("fresh.mp4", size: "640x360", bitrate: "3M")
    FileUtils.touch(VideoVariantGenerator.normalize_path(web))

    assert VideoVariantGenerator.generate(web, "poster")
  end

  test "a queued video counts as optimizing until it's done, even while its jobs wait" do
    web = fake_variants("waiting.mp4", renditions: [])
    File.delete(VideoVariantGenerator.manifest_path(VideoVariantGenerator.normalize_path(web)))
    medium = Medium.create!(file_path: web, media_type: "video", uploaded_at: Time.current)
    VideoVariantGenerator.stubs(:available?).returns(true)
    Rails.cache.delete(VideoVariantGenerator.queue_cache_key(web))

    assert_equal "none", VideoVariantGenerator.status_for(medium)[:state], "nothing queued: original served"
    VideoVariantGenerator.queue!(web)
    assert_equal "queued", medium.reload.variants_status
    VideoVariantGenerator.dequeue(web) # a retrying job's dedup flag going away
    assert_equal "optimizing", VideoVariantGenerator.status_for(medium)[:state]
  ensure
    Rails.cache.delete(VideoVariantGenerator.queue_cache_key(web)) if web
  end

  test "the poster comes from between 10% and 80% of the way through, skipping black frames" do
    web = make_clip("poster-pick.mp4", size: "320x240", seconds: 10)
    source = VideoVariantGenerator.normalize_path(web)
    probe = MediaProbe.call(source)

    20.times do
      at = VideoVariantGenerator.send(:poster_time, source, probe)
      assert at.between?(1.0, 8.0), "#{at}s is outside 10–80% of 10s"
    end

    # A frame read as black is passed over for a brighter one: the first
    # two tries are dark, the third is chosen.
    VideoVariantGenerator.stubs(:rand).returns(0.2, 0.4, 0.6, 0.7)
    VideoVariantGenerator.stubs(:frame_brightness).returns(5, 8, 120, 200)
    assert_in_delta 6.0, VideoVariantGenerator.send(:poster_time, source, probe), 0.01
  end

  test "an all-black video still gets a poster, from its brightest try" do
    web = make_clip("dark.mp4", size: "320x240", seconds: 10)
    source = VideoVariantGenerator.normalize_path(web)
    probe = MediaProbe.call(source)
    VideoVariantGenerator.stubs(:rand).returns(0.2, 0.4, 0.6, 0.7)
    VideoVariantGenerator.stubs(:frame_brightness).returns(3, 9, 6, 2)

    assert_in_delta 4.0, VideoVariantGenerator.send(:poster_time, source, probe), 0.01
  end

  test "transcodes run one at a time on their own queue" do
    assert_equal "video", TranscodeVideoJob.new.queue_name
    assert_equal 1, TranscodeVideoJob.concurrency_limit
  end
end

class VideoRendererTest < ActiveSupport::TestCase
  include VideoTestHelpers

  setup { setup_video_dir }
  teardown { teardown_video_dir }

  test "serves the web versions, smallest first, with poster and size" do
    web = fake_variants("show.mov", renditions: %w[720p 1080p])
    html = VideoRenderer.tag(web, attrs: { "class" => "video-embed", "controls" => true }).to_s

    sources = html.scan(/<source src="([^"]+)"/).flatten
    assert_equal %w[/media/video/variants/show-720p.mp4 /media/video/variants/show-1080p.mp4], sources
    assert_includes html, 'poster="/media/video/variants/show-poster.jpg"'
    assert_includes html, 'width="1280" height="720"'
    assert_includes html, "max-width:100%;height:auto"
    assert_includes html, 'preload="metadata"'
    assert_includes html, "playsinline"
    assert_not_includes html, "show.mov"
  end

  test "falls back to the original when there are no web versions" do
    File.binwrite(File.join(VIDEO_DIR, "plain.mov"), "x")
    @made << "plain.mov"
    html = VideoRenderer.tag("/media/video/plain.mov").to_s

    assert_includes html, '<source src="/media/video/plain.mov" type="video/quicktime">'
    assert_not_includes html, "poster="
    assert_not_includes html, "width="
  end

  test "external URLs and start-time fragments are left alone" do
    assert_equal [ "https://cdn.example.com/a.mp4" ], VideoRenderer.plan("https://cdn.example.com/a.mp4").sources.map { |s| s[:src] }

    web = fake_variants("t.mp4")
    assert_equal "/media/video/variants/t-720p.mp4", VideoRenderer.plan("#{web}#t=10").sources.first[:src]
  end

  test "escapes what it writes" do
    html = VideoRenderer.tag(%(/media/video/a"b.mp4), attrs: { "aria-label" => %(Tom's "clip") }).to_s
    assert_includes html, "a&quot;b.mp4"
    assert_includes html, "Tom&#39;s &quot;clip&quot;"
  end

  test "the markdown embed, player card and video post all use the same player" do
    web = fake_variants("all.mp4")
    post = Post.new(file_path: "posts/v.md", content: "Intro.\n\n![A clip](#{web})\n\nAfter.\n", metadata: {})

    html = post.to_html
    doc = Nokogiri::HTML.fragment(html)
    player = doc.at_css(".video-player-container.video-embed")
    assert player, "an embed gets the site video player"
    assert_equal "video", player["data-player"]
    assert player.at_css("[data-player-ui][hidden] [data-player-part=play]"), "with Roe's controls, shown by player.js"
    assert player.at_css("video[controls][data-player-part=media]"), "and the browser's until then"
    assert_equal "/media/video/variants/all-poster.jpg", player.at_css("video")["poster"]
    assert_equal "A clip", player.at_css("video")["aria-label"]
    assert_includes player.at_css("video source")["src"], "all-720p.mp4"
    assert_nil player.ancestors("p").first, "not left inside a <p> (a <p> can't hold a block)"
    assert_no_match(%r{<p>\s*</p>}, html, "no empty paragraph left behind")

    card = post.send(:render_player_card, { video: web })
    assert_includes card, "all-720p.mp4"
    assert_includes card, "video-player-container player-video"
    assert_includes card, 'data-player="video"'
  end

  test "an embed written with %20 for spaces still finds its web versions" do
    web = fake_variants("has space.mp4")
    post = Post.new(file_path: "posts/v.md", content: "![x](#{web.gsub(' ', '%20')})\n", metadata: {})

    assert_includes post.to_html, "has space-720p.mp4"
  end
end

class VideoVariantProtectionTest < ActiveSupport::TestCase
  test "every video variant traces back to its original, whatever its format" do
    %w[clip-720p.mp4 clip-1080p.mp4 clip-poster.jpg clip-video.json].each do |file|
      candidates = Medium.source_paths_for("/media/video/variants/#{file}")
      assert_includes candidates, "/media/video/clip.mov", file
      assert_includes candidates, "/media/video/clip.mp4", file
      assert_includes candidates, "/media/video/clip.MOV", file
    end
  end

  test "image variants still trace back as before" do
    assert_includes Medium.source_paths_for("/media/images/variants/photo-medium.webp"), "/media/images/photo.jpg"
  end

  test "a file in variants/ with no known suffix is judged on its own path" do
    assert_equal [ "/media/video/variants/random.mp4" ], Medium.source_paths_for("/media/video/variants/random.mp4")
  end

  test "a paid video's web versions are protected" do
    medium = Medium.create!(file_path: "/media/video/members-only.mov", media_type: "video", audience: "paid")
    assert Medium.protected_path?("/media/video/variants/members-only-720p.mp4")
    assert Medium.protected_path?("/media/video/variants/members-only-poster.jpg")
    assert_not Medium.protected_path?("/media/video/variants/someone-else-720p.mp4")
  ensure
    medium&.delete
  end
end
