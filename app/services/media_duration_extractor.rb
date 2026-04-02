class MediaDurationExtractor
  # Extract duration from audio/video file
  # Returns duration in HH:MM:SS format
  def self.extract(file_path)
    return nil unless File.exist?(file_path)

    begin
      movie = FFMPEG::Movie.new(file_path)
      seconds = movie.duration.to_i

      format_duration(seconds)
    rescue => e
      Rails.logger.error "Failed to extract duration from #{file_path}: #{e.message}"
      nil
    end
  end

  # Convert seconds to HH:MM:SS format
  def self.format_duration(seconds)
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    format('%02d:%02d:%02d', hours, minutes, secs)
  end

  # Parse HH:MM:SS back to seconds (for RSS feed)
  def self.parse_duration(duration_string)
    return nil if duration_string.blank?

    parts = duration_string.split(':').map(&:to_i)

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
