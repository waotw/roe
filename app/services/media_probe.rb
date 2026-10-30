# MediaProbe — read an audio or video file's basic facts with ffprobe.
#
#   probe = MediaProbe.call("/path/to/clip.mov")
#   probe.duration      # => 93.4 (seconds, Float) or nil
#   probe.width         # => 1080   — as displayed, after rotation
#   probe.height        # => 1920
#   probe.rotation      # => 90 (degrees) or 0
#   probe.frame_rate    # => 29.97 or nil
#   probe.video_codec   # => "hevc"
#   probe.hdr?          # => true for HLG / PQ footage (iPhone HDR)
#
# Returns nil when ffprobe isn't installed, the file is missing, or ffprobe
# can't read it. Never raises — callers treat nil as "unknown".
#
# ffprobe is run by full path with an argument list (never a shell string),
# so file names with spaces or quotes are passed through untouched.
class MediaProbe
  TIMEOUT = 20 # seconds — reading headers is fast even for a 1GB file

  # Transfer characteristics that mean HDR: HLG (iPhone) and PQ (HDR10).
  HDR_TRANSFERS = %w[arib-std-b67 smpte2084].freeze

  Result = Struct.new(
    :duration, :width, :height, :rotation, :frame_rate,
    :video_codec, :audio_codec, :pixel_format, :color_transfer,
    keyword_init: true
  ) do
    def video? = !video_codec.nil?
    def audio? = !audio_codec.nil?
    def hdr?   = HDR_TRANSFERS.include?(color_transfer.to_s)

    # The shorter side, which is what "720p" / "1080p" measure — so a
    # vertical 1080×1920 phone clip counts as 1080p, not 1920p.
    def short_side = [ width, height ].compact.min
  end

  def self.call(file_path, tool: ManagedTools::Ffmpeg.new)
    new(file_path, tool).call
  end

  def initialize(file_path, tool)
    @file_path = file_path.to_s
    @tool = tool
  end

  def call
    return nil unless File.file?(@file_path)

    ffprobe = @tool.ffprobe_path or return nil
    out, status = ManagedTools::Ffmpeg.capture(
      ffprobe, "-v", "error", "-print_format", "json",
      "-show_format", "-show_streams", @file_path,
      timeout: TIMEOUT
    )
    return nil unless status&.success?

    parse(JSON.parse(out))
  rescue => e
    Rails.logger.warn "[MediaProbe] #{File.basename(@file_path)}: #{e.class}: #{e.message}"
    nil
  end

  private

  def parse(data)
    streams = Array(data["streams"])
    video = streams.find { |s| s["codec_type"] == "video" && !attached_picture?(s) }
    audio = streams.find { |s| s["codec_type"] == "audio" }
    rotation = video ? rotation_of(video) : 0
    width, height = video ? [ video["width"], video["height"] ].map { |n| n&.to_i } : [ nil, nil ]
    width, height = height, width if rotation % 180 != 0

    Result.new(
      duration:       positive_float(data.dig("format", "duration")) || positive_float(video&.dig("duration")) || positive_float(audio&.dig("duration")),
      width:          width,
      height:         height,
      rotation:       rotation,
      frame_rate:     video ? frame_rate_of(video) : nil,
      video_codec:    video&.dig("codec_name"),
      audio_codec:    audio&.dig("codec_name"),
      pixel_format:   video&.dig("pix_fmt"),
      color_transfer: video&.dig("color_transfer")
    )
  end

  # MP3 / M4A cover art is reported as a one-frame "video" stream. It isn't
  # the video, so an audio file with artwork is still just audio.
  def attached_picture?(stream)
    stream.dig("disposition", "attached_pic").to_i == 1
  end

  # Phones record sideways and store a rotation in the display matrix side
  # data (newer ffprobe) or a `rotate` tag (older). Normalised to 0/90/180/270.
  def rotation_of(stream)
    raw = Array(stream["side_data_list"]).filter_map { |sd| sd["rotation"] }.first
    raw ||= stream.dig("tags", "rotate")
    (raw.to_f.round % 360 + 360) % 360
  end

  # "30000/1001" → 29.97. avg_frame_rate is the real rate; r_frame_rate can
  # be a timebase artefact (e.g. 90000/1) on some phone files.
  def frame_rate_of(stream)
    %w[avg_frame_rate r_frame_rate].each do |key|
      num, den = stream[key].to_s.split("/").map(&:to_f)
      next unless num && den && num.positive? && den.positive?

      rate = num / den
      return rate.round(3) if rate.between?(1, 240)
    end
    nil
  end

  def positive_float(value)
    f = Float(value, exception: false)
    f if f&.positive?
  end
end
