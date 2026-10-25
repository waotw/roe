class MediaDurationExtractor
  # Audio Roe reads in plain Ruby (WahWah), so a site with audio but no
  # ffmpeg still gets lengths. Anything else, and audio WahWah can't read,
  # goes to ffprobe.
  AUDIO_EXTENSIONS = %w[mp3 m4a wav ogg oga opus flac aac].freeze

  # The length of what a post's audio: or video: points at, as HH:MM:SS.
  # Nil whenever it can't be confirmed — no value, a file that isn't here,
  # a link that isn't YouTube, a file nothing can read — so a caller that
  # writes the duration only on an answer never replaces a length someone
  # typed with a guess. (Content → Global → "Automatically add audio and
  # video duration"; Admin::PostsController#apply_auto_duration!.)
  def self.for_media(src)
    src = src.to_s.strip
    return nil if src.empty?

    if (embed = VideoEmbed.for(src))
      seconds = embed.duration_seconds.to_i
      return seconds.positive? ? format_duration(seconds) : nil
    end

    file = media_file(src) or return nil
    extract(file)
  rescue => e
    Rails.logger.warn "MediaDurationExtractor.for_media(#{src}): #{e.class}: #{e.message}"
    nil
  end

  # The file on this disk behind a /media/... path: the file itself, or on
  # the live site a video's web version when its original is kept on the
  # writing computer (same length). Nil for anything outside site/media.
  def self.media_file(src)
    return nil unless src.start_with?("/media/") && !src.include?("..")

    path = File.join(RoeSitePaths::SITE_PATH, src.delete_prefix("/"))
    path = VideoVariantGenerator.stand_in_file_for(src) || path unless File.file?(path)
    File.file?(path) ? path : nil
  end

  # Length of an audio or video file as HH:MM:SS. Nil when it can't be read.
  #
  # (This used to call FFMPEG::Movie from the streamio-ffmpeg gem, which was
  # never in the Gemfile, so it always failed quietly and returned nil.)
  def self.extract(file_path)
    seconds = audio_seconds(file_path) if audio?(file_path)
    seconds ||= MediaProbe.call(file_path)&.duration
    seconds.to_f.positive? ? format_duration(seconds.round) : nil
  end

  def self.audio?(file_path)
    AUDIO_EXTENSIONS.include?(File.extname(file_path.to_s).delete_prefix(".").downcase)
  end

  def self.audio_seconds(file_path)
    seconds = WahWah.open(file_path).duration.to_f
    seconds.positive? ? seconds : nil
  rescue => e
    # A damaged file, or a format WahWah doesn't know: ffprobe gets a try.
    Rails.logger.info "WahWah couldn't read #{file_path}: #{e.class}: #{e.message}"
    nil
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
