# Makes one web version of a video (a rendition or the poster) with ffmpeg.
# VideoVariantGenerator.queue! enqueues one of these per file: the poster
# first, then 720p, then 1080p, so the default rendition is ready soonest.
#
# Only one transcode runs at a time, however many are queued, so a batch of
# videos can't slow the site or the computer to a crawl. That's Solid
# Queue's concurrency limit, not a separate worker: the rest wait their
# turn. The limit is held for up to `duration`; a transcode longer than
# that would let a second one start, so it's set well past MAX_TIMEOUT.
class TranscodeVideoJob < ApplicationJob
  queue_as :video

  limits_concurrency to: 1, key: "video-transcode",
                     duration: VideoVariantGenerator::MAX_TIMEOUT + 30.minutes

  # A missing source or tool won't fix itself by retrying. The failure is
  # recorded so the Media Browser can say what went wrong.
  discard_on VideoVariantGenerator::Error do |job, error|
    web_path, name = job.arguments
    Rails.logger.warn "[VideoVariants] #{name} for #{web_path}: #{error.message}"
    VideoVariantGenerator.record_failure(web_path, error.message)
    VideoVariantGenerator.dequeue(web_path)
  end

  # The video is still being copied in (Finder, Site Sync): wait and try
  # again. Up to about ten minutes before calling it a failure. The
  # "queued" status stays put while it waits, so the Media Browser keeps
  # showing it as optimizing.
  retry_on VideoVariantGenerator::StillArriving, wait: 15.seconds, attempts: 40 do |job, error|
    web_path, = job.arguments
    VideoVariantGenerator.record_failure(web_path, "#{error.message} It didn't finish arriving, so it wasn't optimized. Try `bin/rails videos:variants` once it's fully copied.")
    VideoVariantGenerator.dequeue(web_path)
  end

  # Another transcode holds the lock (a retried job can get past Solid
  # Queue's limit while one is running). Step back and come round again;
  # long videos take a while, so this waits up to about a day.
  retry_on VideoVariantGenerator::Busy, wait: 30.seconds, attempts: 3000

  def perform(web_path, name, force = false)
    Rails.logger.info "[VideoVariants] Making #{name} for #{web_path}"
    VideoVariantGenerator.generate(web_path, name, force: force)
    VideoVariantGenerator.dequeue(web_path) if name == VideoVariantGenerator::RENDITIONS.keys.last
  end
end
