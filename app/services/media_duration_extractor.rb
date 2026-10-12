class MediaDurationExtractor
  # Length of an audio or video file as HH:MM:SS, read with ffprobe.
  # nil when ffprobe isn't installed or can't read the file — the editor
  # falls back to reading the length in the browser.
  #
  # (This used to call FFMPEG::Movie from the streamio-ffmpeg gem, which was
  # never in the Gemfile, so it always failed quietly and returned nil.)
  def self.extract(file_path)
    seconds = MediaProbe.call(file_path)&.duration
    seconds ? format_duration(seconds.round) : nil
  end

  # Convert seconds to HH:MM:SS format
  def self.format_duration(seconds)
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    format("%02d:%02d:%02d", hours, minutes, secs)
  end

  # Parse HH:MM:SS back to seconds (for RSS feed)
  def self.parse_duration(duration_string)
    return nil if duration_string.blank?

    parts = duration_string.split(":").map(&:to_i)

    case parts.length
    when 3 # HH:MM:SS
      parts[0] * 3600 + parts[1] * 60 + parts[2]
    when 2 # MM:SS
      parts[0] * 60 + parts[1]
    when 1 # SS
      parts[0]
    else
      nil
    end
  end
end
