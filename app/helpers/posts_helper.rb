module PostsHelper
  def format_duration(duration)
    # Handle both "HH:MM:SS" and seconds formats
    if duration.to_s.include?(':')
      duration # Already formatted
    else
      # Convert seconds to HH:MM:SS
      seconds = duration.to_i
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60

      if hours > 0
        "%d:%02d:%02d" % [hours, minutes, secs]
      else
        "%d:%02d" % [minutes, secs]
      end
    end
  end
end
