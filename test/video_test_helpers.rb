# Shared by the video variant tests: tiny clips made with ffmpeg (skipped
# where it isn't installed) and hand-written manifests, as Site Sync would
# bring them to a live site without ffmpeg.
module VideoTestHelpers
  VIDEO_DIR = File.join(RoeSitePaths::SITE_PATH, "media", "video").freeze

  def setup_video_dir
    @made = []
    FileUtils.mkdir_p(VIDEO_DIR)
  end

  def teardown_video_dir
    @made.each { |name| VideoVariantGenerator.delete_variants(File.join(VIDEO_DIR, name)) }
    @made.each { |name| FileUtils.rm_f(File.join(VIDEO_DIR, name)) }
  end

  def ffmpeg_tool = ManagedTools::Ffmpeg.new

  # A short clip made with ffmpeg's built-in test pattern. `rotate` sets the
  # phone-style rotation flag; `hevc_10bit` makes it look like iPhone footage.
  def make_clip(name, size: "640x360", seconds: 2, rate: 30, rotate: nil, hevc_10bit: false, bitrate: nil)
    skip "ffmpeg not installed" unless ffmpeg_tool.installed?

    path = File.join(VIDEO_DIR, name)
    flat = rotate ? path.sub(/(\.\w+)\z/, '-flat\1') : path
    codec = hevc_10bit ? %w[-c:v libx265 -pix_fmt yuv420p10le -tag:v hvc1 -x265-params log-level=error] : %w[-c:v libx264 -pix_fmt yuv420p]
    codec += [ "-b:v", bitrate ] if bitrate
    ok = system(ffmpeg_tool.ffmpeg_path, "-v", "error", "-y",
                "-f", "lavfi", "-i", "testsrc2=size=#{size}:rate=#{rate}",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
                "-t", seconds.to_s, *codec, "-c:a", "aac", "-shortest",
                "-metadata", "location=+40.7128-074.0060/", flat)
    skip "this ffmpeg can't make test clips" unless ok
    if rotate
      system(ffmpeg_tool.ffmpeg_path, "-v", "error", "-y", "-display_rotation", rotate.to_s, "-i", flat, "-c", "copy", path)
      FileUtils.rm_f(flat)
    end
    # Backdated: a file written in the last few seconds counts as still
    # being copied in (VideoVariantGenerator.still_arriving?).
    File.utime(Time.now - 60, Time.now - 60, path)
    @made << name
    "/media/video/#{name}"
  end

  def make_all(web_path)
    [ VideoVariantGenerator::POSTER, *VideoVariantGenerator::RENDITIONS.keys ].map do |n|
      VideoVariantGenerator.generate(web_path, n)
    end
  end

  # A manifest written by hand, as Site Sync would bring it to a live site.
  # `key:` names its list of web versions: "variants" as Roe writes it, or
  # "renditions" as manifests before 0.4.0 did.
  def fake_variants(name, renditions: %w[720p], poster: true, size: nil, key: VideoVariantGenerator::MANIFEST_LIST)
    source = File.join(VIDEO_DIR, name)
    File.binwrite(source, "x" * 1000) unless File.exist?(source)
    @made << name
    FileUtils.mkdir_p(File.join(VIDEO_DIR, "variants"))
    base = File.basename(name, ".*")
    entries = renditions.map do |r|
      File.binwrite(VideoVariantGenerator.variant_path_for(source, r), "v")
      { "name" => r, "path" => "/media/video/variants/#{base}-#{r}.mp4", "size" => 1, "width" => 1280, "height" => 720 }
    end
    File.binwrite(VideoVariantGenerator.variant_path_for(source, "poster"), "p") if poster
    manifest = {
      "source" => { "path" => "/media/video/#{name}", "size" => size || File.size(source) },
      key => entries,
      "poster" => (poster ? "/media/video/variants/#{base}-poster.jpg" : nil),
      "complete" => true
    }
    File.write(VideoVariantGenerator.manifest_path(source), manifest.to_json)
    "/media/video/#{name}"
  end
end
