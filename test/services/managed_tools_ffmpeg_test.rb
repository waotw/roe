require "test_helper"

# ffmpeg is an optional managed tool. These tests stub where the programs
# are found and what they print, so they pass on machines with or without
# ffmpeg installed. The last test in MediaProbeRealFileTest runs the real
# ffprobe when it's available and skips otherwise.
class ManagedToolsFfmpegTest < ActiveSupport::TestCase
  OK = Struct.new(:ok) { def success? = ok }

  setup { @tool = ManagedTools::Ffmpeg.new }

  def stub_paths(ffmpeg:, ffprobe:)
    @tool.stubs(:ffmpeg_path).returns(ffmpeg)
    @tool.stubs(:ffprobe_path).returns(ffprobe)
  end

  test "is listed in the registry" do
    assert_equal @tool.class, ManagedTools.find(:ffmpeg).class
  end

  test "installed when both ffmpeg and ffprobe are found and run" do
    stub_paths(ffmpeg: "/x/ffmpeg", ffprobe: "/x/ffprobe")
    ManagedTools::Ffmpeg.stubs(:capture).returns([ "ffmpeg version 8.0.1 Copyright", OK.new(true) ])

    assert @tool.installed?
    assert_equal "8.0.1", @tool.version
    assert_equal [], @tool.missing
    assert_nil @tool.note
  end

  test "not installed when ffprobe is missing, with a note saying which" do
    stub_paths(ffmpeg: "/x/ffmpeg", ffprobe: nil)
    ManagedTools::Ffmpeg.stubs(:capture).returns([ "", OK.new(true) ])

    assert_not @tool.installed?
    assert_equal [ "ffprobe" ], @tool.missing
    assert_match(/Found ffmpeg but not ffprobe/, @tool.note)
    assert_match(/Found ffmpeg but not ffprobe/, @tool.status[:note])
  end

  test "no note when neither is installed" do
    stub_paths(ffmpeg: nil, ffprobe: nil)

    assert_not @tool.installed?
    assert_nil @tool.note
  end

  test "not installed when the program is there but won't run" do
    stub_paths(ffmpeg: "/x/ffmpeg", ffprobe: "/x/ffprobe")
    ManagedTools::Ffmpeg.stubs(:capture).returns([ "dyld: Library not loaded", OK.new(false) ])

    assert_not @tool.installed?
  end

  test "snapshot builds report their build id as the version" do
    stub_paths(ffmpeg: "/x/ffmpeg", ffprobe: "/x/ffprobe")
    ManagedTools::Ffmpeg.stubs(:capture).returns([ "ffmpeg version N-121489-g7f7335ec43-tessus https://evermeet.cx", OK.new(true) ])

    assert_equal "N-121489-g7f7335ec43-tessus", @tool.version
  end

  test "the package manager command is the ffmpeg package on every manager" do
    brew = ManagedTools::Platform.new(os: :macos, package_manager: :brew)
    brew.stubs(:homebrew_bottle?).returns(true)
    apt  = ManagedTools::Platform.new(os: :linux, package_manager: :apt)

    assert_equal "brew install ffmpeg", @tool.install_command(brew)
    assert_match(/apt-get install -y ffmpeg\z/, @tool.install_command(apt))
  end

  test "a builder's web address is dropped from the version" do
    stub_paths(ffmpeg: "/x/ffmpeg", ffprobe: "/x/ffprobe")
    ManagedTools::Ffmpeg.stubs(:capture).returns([ "ffmpeg version 9.0.2-https://www.martin-riedl.de Copyright", OK.new(true) ])

    assert_equal "9.0.2", @tool.version
  end

  test "ffmpeg and ffprobe are taken from the same folder when one has both" do
    Dir.mktmpdir do |root|
      lone = File.join(root, "lone")
      pair = File.join(root, "pair")
      [ [ lone, %w[ffmpeg] ], [ pair, %w[ffmpeg ffprobe] ] ].each do |dir, names|
        FileUtils.mkdir_p(dir)
        names.each { |n| File.write(File.join(dir, n), "#!/bin/sh\n").then { File.chmod(0o755, File.join(dir, n)) } }
      end
      ManagedTools::Platform.stubs(:search_dirs).returns([ lone, pair ])

      assert_equal File.join(pair, "ffmpeg"), @tool.ffmpeg_path
      assert_equal File.join(pair, "ffprobe"), @tool.ffprobe_path
    end
  end

  test "capture kills a program that runs past its timeout" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _out, status = ManagedTools::Ffmpeg.capture("sleep", "5", timeout: 0.3)

    assert_nil status
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
  end

  test "find_executable checks PATH, then the extra bin dirs" do
    Dir.mktmpdir do |dir|
      exe = File.join(dir, "roe-test-tool")
      File.write(exe, "#!/bin/sh\n")
      File.chmod(0o755, exe)

      with_path(dir) { assert_equal exe, ManagedTools::Platform.find_executable("roe-test-tool") }
      with_path("/nonexistent") { assert_nil ManagedTools::Platform.find_executable("roe-test-tool") }
    end
  end

  private

  def with_path(path)
    original = ENV["PATH"]
    ENV["PATH"] = path
    yield
  ensure
    ENV["PATH"] = original
  end
end

# MediaProbe parses ffprobe's JSON. These feed it recorded output for the
# cases that matter for video work: phone rotation, cover art on audio,
# HDR, and odd frame-rate fields.
class MediaProbeParseTest < ActiveSupport::TestCase
  OK = Struct.new(:ok) { def success? = ok }

  setup do
    @file = Tempfile.new([ "probe", ".mov" ])
    @tool = ManagedTools::Ffmpeg.new
    @tool.stubs(:ffprobe_path).returns("/x/ffprobe")
  end

  teardown { @file.close! }

  def probe(json, success: true)
    ManagedTools::Ffmpeg.stubs(:capture).returns([ json.to_json, OK.new(success) ])
    MediaProbe.call(@file.path, tool: @tool)
  end

  test "a vertical phone clip reports its displayed size and counts as 1080p" do
    result = probe({
      "format" => { "duration" => "93.400000" },
      "streams" => [
        { "codec_type" => "video", "codec_name" => "hevc", "width" => 1920, "height" => 1080,
          "avg_frame_rate" => "30000/1001", "r_frame_rate" => "90000/1", "pix_fmt" => "yuv420p10le",
          "color_transfer" => "arib-std-b67",
          "side_data_list" => [ { "side_data_type" => "Display Matrix", "rotation" => -90 } ] },
        { "codec_type" => "audio", "codec_name" => "aac" }
      ]
    })

    assert_in_delta 93.4, result.duration
    assert_equal 270, result.rotation
    assert_equal [ 1080, 1920 ], [ result.width, result.height ]
    assert_equal 1080, result.short_side
    assert_in_delta 29.97, result.frame_rate, 0.01
    assert result.hdr?
    assert result.video?
    assert result.audio?
  end

  test "older files with a rotate tag are honoured too" do
    result = probe({
      "format" => { "duration" => "3" },
      "streams" => [ { "codec_type" => "video", "codec_name" => "h264", "width" => 1280, "height" => 720,
                       "avg_frame_rate" => "30/1", "tags" => { "rotate" => "90" } } ]
    })

    assert_equal 90, result.rotation
    assert_equal [ 720, 1280 ], [ result.width, result.height ]
    assert_not result.hdr?
  end

  test "cover art on an audio file is not mistaken for video" do
    result = probe({
      "format" => { "duration" => "185.2" },
      "streams" => [
        { "codec_type" => "audio", "codec_name" => "mp3" },
        { "codec_type" => "video", "codec_name" => "mjpeg", "width" => 600, "height" => 600,
          "disposition" => { "attached_pic" => 1 } }
      ]
    })

    assert_not result.video?
    assert result.audio?
    assert_nil result.width
  end

  test "duration falls back to the stream when the container has none" do
    result = probe({
      "format" => {},
      "streams" => [ { "codec_type" => "video", "codec_name" => "vp9", "duration" => "12.5",
                       "width" => 640, "height" => 360, "avg_frame_rate" => "0/0", "r_frame_rate" => "25/1" } ]
    })

    assert_in_delta 12.5, result.duration
    assert_in_delta 25.0, result.frame_rate
  end

  test "nil when ffprobe fails, isn't installed, or the file is missing" do
    assert_nil probe({}, success: false)

    @tool.stubs(:ffprobe_path).returns(nil)
    assert_nil MediaProbe.call(@file.path, tool: @tool)

    assert_nil MediaProbe.call("/nonexistent/clip.mp4", tool: @tool)
  end

  test "nil, not an exception, when ffprobe prints something that isn't JSON" do
    ManagedTools::Ffmpeg.stubs(:capture).returns([ "not json", OK.new(true) ])
    assert_nil MediaProbe.call(@file.path, tool: @tool)
  end

  test "MediaDurationExtractor formats the probed length" do
    MediaProbe.stubs(:call).returns(MediaProbe::Result.new(duration: 3725.6))
    assert_equal "01:02:06", MediaDurationExtractor.extract(@file.path)

    MediaProbe.stubs(:call).returns(nil)
    assert_nil MediaDurationExtractor.extract(@file.path)
  end
end

# End to end with the real ffmpeg + ffprobe, when this machine has them.
class MediaProbeRealFileTest < ActiveSupport::TestCase
  test "probes a real rotated clip and an mp3" do
    tool = ManagedTools::Ffmpeg.new
    skip "ffmpeg and ffprobe not installed" unless tool.installed?

    Dir.mktmpdir do |dir|
      clip = File.join(dir, "clip with spaces.mov")
      tone = File.join(dir, "tone.mp3")
      ok = system(tool.ffmpeg_path, "-v", "error", "-y",
                  "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=25",
                  "-f", "lavfi", "-i", "sine=frequency=440",
                  "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
                  File.join(dir, "flat.mp4")) &&
           system(tool.ffmpeg_path, "-v", "error", "-y", "-display_rotation", "90",
                  "-i", File.join(dir, "flat.mp4"), "-c", "copy", clip) &&
           system(tool.ffmpeg_path, "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440",
                  "-t", "3", tone)
      skip "this ffmpeg build couldn't make test files" unless ok

      video = MediaProbe.call(clip)
      assert_equal [ 240, 320 ], [ video.width, video.height ]
      assert_equal 90, video.rotation
      assert_in_delta 2.0, video.duration, 0.2
      assert_equal "h264", video.video_codec

      assert_equal "00:00:03", MediaDurationExtractor.extract(tone)
      assert_not MediaProbe.call(tone).video?
    end
  end
end
