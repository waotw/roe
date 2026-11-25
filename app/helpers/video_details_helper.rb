# The Media Browser's video window (Admin::MediumController#details).
module VideoDetailsHelper
  # 239.52 → "3:59", 3725 → "1:02:05".
  def video_time(seconds)
    total = seconds.to_f.floor
    total = 0 if total.negative?
    hours, rest = total.divmod(3600)
    minutes, secs = rest.divmod(60)
    hours.positive? ? format("%d:%02d:%02d", hours, minutes, secs) : format("%d:%02d", minutes, secs)
  end

  # Where the poster came from, under POSTER NOW
  # (VideoVariantGenerator.poster_choice).
  # COPY: poster captions in the video window
  def video_poster_caption(choice)
    return "No poster yet." if choice.nil?

    case choice[:from]
    when "frame" then "Frame at #{video_time(choice[:at])} · chosen"
    when "image" then "Image: #{File.basename(choice[:image].to_s)}"
    else choice[:at] ? "Frame at #{video_time(choice[:at])} · picked by Roe" : "Picked by Roe"
    end
  end

  # The points the JUMP TO strip shows: `count` moments spread evenly
  # through the video, each in the middle of its stretch.
  def video_jump_points(duration, count: 8)
    duration = duration.to_f
    return [] unless duration.positive?

    Array.new(count) { |i| (duration * (i + 0.5) / count).round(2) }
  end
end
