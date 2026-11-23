require "test_helper"
require_relative "../video_test_helpers"

# Choosing a video's poster by hand (the Media Browser's video window): a
# moment in the video or an image from the library becomes the same
# <name>-poster.jpg, the manifest records the choice, and making the web
# versions again keeps it. Real ffmpeg on tiny clips; skipped without it.
class VideoPosterChoiceTest < ActiveSupport::TestCase
  include VideoTestHelpers

  IMAGE_DIR = File.join(RoeSitePaths::SITE_PATH, "media", "images", "poster_choice_test").freeze

  setup do
    setup_video_dir
    FileUtils.mkdir_p(IMAGE_DIR)
  end

  teardown do
    teardown_video_dir
    FileUtils.rm_rf(IMAGE_DIR)
  end

  # Two seconds of red, then two of blue: which half a poster came from is
  # its colour.
  def make_two_colour_clip(name)
    skip "ffmpeg not installed" unless ffmpeg_tool.installed?

    path = File.join(VIDEO_DIR, name)
    ok = system(ffmpeg_tool.ffmpeg_path, "-v", "error", "-y",
                "-f", "lavfi", "-i", "color=c=red:s=320x180:r=25:d=2",
                "-f", "lavfi", "-i", "color=c=blue:s=320x180:r=25:d=2",
                "-filter_complex", "[0][1]concat=n=2:v=1:a=0,format=yuv420p",
                "-c:v", "libx264", path)
    skip "this ffmpeg can't make test clips" unless ok
    File.utime(Time.now - 60, Time.now - 60, path)
    @made << name
    "/media/video/#{name}"
  end

  def make_image(name, colour, size: "400x400")
    path = File.join(IMAGE_DIR, name)
    assert system(ffmpeg_tool.ffmpeg_path, "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=#{colour}:s=#{size}",
                  "-frames:v", "1", path)
    "/media/images/poster_choice_test/#{name}"
  end

  def poster_path(web) = VideoVariantGenerator.variant_path_for(VideoVariantGenerator.normalize_path(web), "poster")

  # The poster's average colour, as the strongest channel.
  def poster_colour(web)
    out, = ManagedTools::Platform.run(ffmpeg_tool.ffmpeg_path, "-v", "error", "-i", poster_path(web),
                                      "-vf", "scale=1:1", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1", timeout: 20)
    r, g, b = out.bytes
    { r => :red, g => :green, b => :blue }[[ r, g, b ].max]
  end

  def manifest(web) = VideoVariantGenerator.current_manifest(web)

  test "a chosen frame becomes the poster, and the manifest says so" do
    web = make_two_colour_clip("choose-frame.mp4")
    VideoVariantGenerator.generate(web, "poster")
    VideoVariantGenerator.choose_poster_frame!(web, 3.0)

    assert_equal :blue, poster_colour(web)
    assert_equal "frame", manifest(web)["poster_from"]
    assert_in_delta 3.0, manifest(web)["poster_at"], 0.01
    assert_equal({ from: "frame", at: 3.0 }, VideoVariantGenerator.poster_choice(manifest(web)))
  end

  test "making the web versions again keeps the chosen frame" do
    web = make_two_colour_clip("keep-frame.mp4")
    make_all(web)
    VideoVariantGenerator.choose_poster_frame!(web, 0.5)
    assert_equal :red, poster_colour(web)

    # A forced rebuild would otherwise pick a random 10–80% point (here:
    # in the blue half).
    VideoVariantGenerator.stubs(:rand).returns(0.75)
    VideoVariantGenerator.generate(web, "poster", force: true)
    VideoVariantGenerator.generate(web, "720p", force: true)

    assert_equal :red, poster_colour(web)
    assert_equal "frame", manifest(web)["poster_from"]
    assert_in_delta 0.5, manifest(web)["poster_at"], 0.01
    assert manifest(web)["complete"]
  end

  test "a chosen frame whose poster file was deleted is made again from the same moment" do
    web = make_two_colour_clip("deleted-frame.mp4")
    make_all(web)
    VideoVariantGenerator.choose_poster_frame!(web, 0.5)
    File.delete(poster_path(web))

    VideoVariantGenerator.stubs(:rand).returns(0.75)
    VideoVariantGenerator.generate(web, "poster")

    assert_equal :red, poster_colour(web)
    assert_equal "frame", manifest(web)["poster_from"]
  end

  test "a chosen image is cut to the video's shape and copied in" do
    web = make_two_colour_clip("choose-image.mp4")
    make_all(web)
    image = make_image("still.png", "green", size: "400x400")

    VideoVariantGenerator.choose_poster_image!(web, image)

    probe = MediaProbe.call(poster_path(web))
    assert_equal [ 320, 180 ], [ probe.width, probe.height ], "cut to fill the video's shape"
    assert_equal :green, poster_colour(web)
    assert_equal "image", manifest(web)["poster_from"]
    assert_equal image, manifest(web)["poster_image"]
    assert_nil manifest(web)["poster_at"]

    # Deleting the image doesn't touch the poster: it's a copy.
    FileUtils.rm_f(File.join(IMAGE_DIR, "still.png"))
    assert_equal :green, poster_colour(web)
    assert VideoVariantGenerator.complete?(web)
  end

  test "making the web versions again cuts the chosen image again, or picks a frame once it's gone" do
    web = make_two_colour_clip("rebuild-image.mp4")
    make_all(web)
    image = make_image("again.png", "green")
    VideoVariantGenerator.choose_poster_image!(web, image)

    VideoVariantGenerator.generate(web, "poster", force: true)
    assert_equal :green, poster_colour(web)
    assert_equal "image", manifest(web)["poster_from"]

    FileUtils.rm_f(File.join(IMAGE_DIR, "again.png"))
    VideoVariantGenerator.stubs(:rand).returns(0.75)
    VideoVariantGenerator.generate(web, "poster", force: true)

    assert_equal :blue, poster_colour(web), "Roe picks a frame again"
    assert_nil manifest(web)["poster_from"]
    assert_nil manifest(web)["poster_image"]
    assert manifest(web)["poster_at"]
  end

  test "a video that was never optimized can still be given a poster" do
    web = make_two_colour_clip("never-optimized.mp4")
    VideoVariantGenerator.choose_poster_frame!(web, 3.0)

    assert_equal :blue, poster_colour(web)
    assert_not manifest(web)["complete"], "its web versions are still to make"

    # Optimizing it later keeps the choice.
    VideoVariantGenerator.stubs(:rand).returns(0.2)
    make_all(web)
    assert_equal :blue, poster_colour(web)
    assert manifest(web)["complete"]
  end

  test "a time past the end takes the last frame; anything but a library image is refused" do
    web = make_two_colour_clip("edges.mp4")
    VideoVariantGenerator.choose_poster_frame!(web, 999)
    assert_equal :blue, poster_colour(web)
    assert_operator manifest(web)["poster_at"], :<, 4.0

    [ "/etc/passwd", "/media/../config/master.key", "/media/images/variants/x-small.webp", "/media/images/nope.png", web ].each do |bad|
      assert_raises(VideoVariantGenerator::Error, bad) { VideoVariantGenerator.choose_poster_image!(web, bad) }
    end
  end

  test "JUMP TO stills are kept outside site/" do
    web = make_two_colour_clip("strip.mp4")
    still = VideoVariantGenerator.frame_preview(web, 3.0)

    assert still.start_with?(Rails.root.join("tmp").to_s)
    assert_equal still, VideoVariantGenerator.frame_preview(web, 3.0), "made once, then reused"
    assert_equal 160, MediaProbe.call(still).width
  end
end
