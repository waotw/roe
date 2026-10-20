# frozen_string_literal: true

require "open3"

# VideoVariantGenerator — makes small, fast-starting web versions of an
# uploaded video with ffmpeg: a 720p and (when the source is big enough) a
# 1080p H.264 MP4, plus a poster frame. The original is never changed.
#
#   site/media/video/clip.mov                       the original
#   site/media/video/variants/clip-720p.mp4         served by default
#   site/media/video/variants/clip-1080p.mp4        offered as a second source
#   site/media/video/variants/clip-poster.jpg       shown before playback
#   site/media/video/variants/clip-video.json       what was made (see below)
#
# Video is processed on the computer where you write (ffmpeg is a local
# tool for 0.4.0) and the files under variants/ go to the live site with
# Site Sync — only media/images/variants is left out of sync, because
# images are quick to rebuild and video isn't.
#
# The manifest (clip-video.json) records each rendition's size and
# dimensions, so the page can be rendered — width, height, poster — on a
# live site that has no ffmpeg or ffprobe at all. It also records the
# original's size, so a replaced original is noticed and its old renditions
# are ignored instead of served.
#
# The encode settings are where most of the size saving comes from; see
# ENCODE and #encode_args.
class VideoVariantGenerator
  # The renditions, smallest first. `short` is the length of the shorter
  # side, so a vertical 1080×1920 phone clip counts as 1080p rather than
  # being squeezed to 1080 tall.
  #   crf      quality (lower = better and bigger). 23 is x264's default.
  #   maxrate  ceiling so one busy scene can't balloon the file
  RENDITIONS = {
    "720p"  => { short: 720,  crf: 24, maxrate: "2500k", bufsize: "5000k" },
    "1080p" => { short: 1080, crf: 23, maxrate: "5000k", bufsize: "10000k" }
  }.freeze

  DEFAULT_RENDITION = "720p"

  # Shared encode settings. medium is x264's default preset; slower presets
  # save a little more space but take noticeably longer on a laptop.
  ENCODE = {
    preset: "medium",
    audio_bitrate: "128k",
    max_frame_rate: 30
  }.freeze

  POSTER = "poster"

  # The share of the way through a video the poster is taken from: a random
  # point in this range. Many videos open on black, a title card or a
  # fade-in, so not the first frames, and not the closing credits.
  POSTER_RANGE = (0.10..0.80)

  # Each candidate frame is read as a tiny greyscale thumbnail; one this
  # dark on average (0–255) is taken to be black and another is tried.
  POSTER_MIN_BRIGHTNESS = 24
  POSTER_TRIES = 4
  MANIFEST_SUFFIX = "-video.json"
  VIDEO_EXTENSIONS = %w[.mp4 .m4v .mov .webm .mkv .avi .ogv].freeze

  # Containers browsers play directly. An original in one of these, already
  # H.264 8-bit SDR, can be served as-is when a rendition wouldn't be smaller.
  WEB_READY_EXTENSIONS = %w[.mp4 .m4v].freeze

  # Room to leave on the disk on top of the expected output, in bytes.
  DISK_MARGIN = 200 * 1024 * 1024

  # A rendition has to save at least this share of an already web-ready
  # original's size to be worth keeping; otherwise the original is served
  # and there's no near-duplicate copy taking up space.
  MIN_SAVING = 0.10

  # A transcode that runs far longer than this is stuck, not slow.
  MIN_TIMEOUT = 10 * 60
  MAX_TIMEOUT = 6 * 60 * 60

  QUEUE_DEDUP_TTL = 6.hours

  class Error < StandardError; end

  # The source file is still being written (a copy or sync in progress).
  # Not a failure: the job tries again shortly.
  class StillArriving < StandardError; end

  # Another transcode is running (see with_transcode_lock). Not a failure:
  # the job tries again shortly.
  class Busy < StandardError; end

  # A file whose size changes over this many seconds is taken to still be
  # arriving.
  SETTLE_SECONDS = 2

  class << self
    # ── Can we make renditions here? ────────────────────────────────────

    def tool = ManagedTools::Ffmpeg.new

    # ffmpeg and ffprobe both installed and working. Production normally
    # says no (no ffmpeg in the image) and serves what Site Sync brought.
    def available?
      tool.installed?
    end

    def video_file?(path)
      VIDEO_EXTENSIONS.include?(File.extname(path.to_s).downcase)
    end

    def variant_path?(path)
      path.to_s.split("/").include?("variants")
    end

    # ── Paths ───────────────────────────────────────────────────────────

    # Absolute path on disk for a web path (/media/video/x.mov) or an
    # absolute path, the same rules as ImageVariantGenerator.normalize_path.
    def normalize_path(path) = ImageVariantGenerator.normalize_path(path)

    def web_path_for(absolute)
      "/" + absolute.to_s.sub(%r{\A#{Regexp.escape(RoeSitePaths::SITE_PATH.to_s)}/?}, "")
    end

    def variants_dir(source) = File.join(File.dirname(normalize_path(source)), "variants")

    def base_name(source) = File.basename(source.to_s, ".*")

    # name is a rendition ("720p"), "poster", or nil for the manifest.
    def variant_path_for(source, name)
      dir = variants_dir(source)
      base = base_name(source)
      case name
      when POSTER then File.join(dir, "#{base}-#{POSTER}.jpg")
      when nil    then File.join(dir, "#{base}#{MANIFEST_SUFFIX}")
      else File.join(dir, "#{base}-#{name}.mp4")
      end
    end

    def manifest_path(source) = variant_path_for(source, nil)

    # Every file name this generator could make for a source, for cleanup
    # and for tracing a variant back to its (possibly paid) original.
    def all_variant_paths(source)
      (RENDITIONS.keys + [ POSTER, nil ]).map { |name| variant_path_for(source, name) }
    end

    # The suffixes a video variant file name ends in: "-720p", "-1080p",
    # "-poster", "-video". Medium.source_paths_for strips these to find the
    # original a variant came from.
    def variant_suffixes
      RENDITIONS.keys + [ POSTER, MANIFEST_SUFFIX.delete_prefix("-").delete_suffix(".json") ]
    end

    # ── What a source needs ─────────────────────────────────────────────

    # The renditions worth making for a source whose shorter side is
    # `short`: every rendition at or below the source size, and always the
    # smallest one (made at the source's own size when the source is
    # smaller than 720p — never upscaled).
    def rendition_names_for(short)
      return [ RENDITIONS.keys.first ] if short.nil? || short <= 0

      names = RENDITIONS.select { |_, spec| spec[:short] <= short }.keys
      names.presence || [ RENDITIONS.keys.first ]
    end

    # The frame rate to encode at. Up to 30 is kept. 50 and 60 fps are
    # kept too, so smooth motion stays smooth. Anything faster (phones
    # record 120 and 240 for slow motion) is halved until it's 30 or under,
    # which drops whole frames evenly instead of stuttering.
    def target_frame_rate(rate)
      return nil if rate.nil? || rate <= 0
      return nil if rate <= ENCODE[:max_frame_rate] + 0.5
      return nil if rate.between?(47.0, 61.0)

      target = rate
      target /= 2 while target > ENCODE[:max_frame_rate] + 0.5
      target >= 23.5 ? target.round(3) : ENCODE[:max_frame_rate]
    end

    # ── Manifest ────────────────────────────────────────────────────────

    def read_manifest(source)
      read_manifest_file(manifest_path(source))
    end

    def read_manifest_file(path)
      return nil unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # The manifest, only if it was made from the original as it is now. A
    # replaced original (different size) makes the old renditions stale.
    #
    # On the live site the original may not be there at all: the live-video
    # setting keeps originals on the computer you write on
    # (SiteSync::LiveVideo). There the manifest is all there is to go on, and
    # it's trusted — live never makes renditions, so it can't hold a stale
    # set; whatever Site Sync brought is current.
    def current_manifest(source)
      manifest = read_manifest(source) or return nil
      source_abs = normalize_path(source)
      return (stand_in_allowed? ? manifest : nil) unless File.file?(source_abs)
      return nil unless manifest.dig("source", "size") == File.size(source_abs)

      manifest
    end

    # Whether a missing original can be stood in for by its manifest. Only on
    # the live site: on the computer you write on, a missing original means
    # you deleted it, and its web versions should go with it.
    def stand_in_allowed? = SiteSync::LiveVideo.live_side?

    # The file on disk that stands in for one original (/media/video/clip.mov)
    # missing from it: its smallest web version. Nil if the original is
    # here, isn't a video, or has no web versions — and always nil on the
    # writing computer, where a missing original means it was deleted. For
    # the editor's checks on live: "is this file there?" and "how long is it?"
    # (the web versions are the same length).
    def stand_in_file_for(web_path)
      return nil unless stand_in_allowed?

      web = web_path.to_s
      return nil unless web.start_with?("/media/") && !web.include?("..")
      return nil unless video_file?(web) && !variant_path?(web)

      source = normalize_path(web)
      return nil if File.file?(source)

      smallest = available_renditions(source).first or return nil
      variant_path_for(source, smallest["name"])
    end

    # Web paths (/media/video/clip.mov) of originals that aren't on this
    # disk but whose web versions are — on the live site, the videos whose
    # originals the live-video setting keeps on the writing computer. Each
    # still counts as a video: its media record stays, a post that names it
    # isn't missing media, and the player plays its web versions. Empty on
    # the writing computer.
    def stand_in_originals
      return [] unless stand_in_allowed?

      Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media", "**", "variants", "*#{MANIFEST_SUFFIX}")).filter_map do |path|
        manifest = read_manifest_file(path) or next
        web = manifest.dig("source", "path").to_s
        next unless web.start_with?("/media/") && video_file?(web) && !variant_path?(web)

        source = normalize_path(web)
        # The manifest must sit in this original's own variants folder, so a
        # hand-edited one can't vouch for a file somewhere else.
        next unless File.expand_path(manifest_path(source)) == File.expand_path(path)
        next if File.file?(source)
        next if available_renditions(source).empty?

        web
      end
    end

    # Renditions in the manifest whose files are on disk, smallest first.
    def available_renditions(source)
      manifest = current_manifest(source) or return []
      Array(manifest["renditions"]).select do |r|
        RENDITIONS.key?(r["name"]) && File.file?(variant_path_for(source, r["name"]))
      end.sort_by { |r| RENDITIONS.keys.index(r["name"]) }
    end

    # The web versions are all there: the manifest says complete AND the
    # poster and every rendition it lists are still on disk. Files deleted
    # by hand (or lost some other way) mean it isn't complete any more,
    # whatever the manifest or the database say.
    def complete?(source)
      manifest = current_manifest(source) or return false
      return false unless manifest["complete"] == true
      return false if manifest["poster"].present? && !File.file?(variant_path_for(source, POSTER))

      Array(manifest["renditions"]).all? do |r|
        RENDITIONS.key?(r["name"]) && File.file?(variant_path_for(source, r["name"]))
      end
    end

    # ── Queueing ────────────────────────────────────────────────────────

    # Queue the poster and each needed rendition as separate jobs (they run
    # one at a time — see TranscodeVideoJob). Skipped when ffmpeg isn't
    # here, for a variant path, or when this original's renditions are
    # already complete. force: true rebuilds everything.
    def queue!(web_path, force: false)
      return false unless available?
      return false if variant_path?(web_path)

      source = normalize_path(web_path)
      return false unless video_file?(source) && File.file?(source)
      return false if !force && complete?(source)

      cache_key = queue_cache_key(web_path)
      return false if !force && Rails.cache.exist?(cache_key)

      Rails.cache.write(cache_key, true, expires_in: QUEUE_DEDUP_TTL)
      set_status(web_path, "queued")
      TranscodeVideoJob.perform_later(web_path, POSTER, force)
      RENDITIONS.each_key { |name| TranscodeVideoJob.perform_later(web_path, name, force) }
      true
    end

    def dequeue(web_path) = Rails.cache.delete(queue_cache_key(web_path))

    def queue_cache_key(web_path) = "video_variants_queued:#{web_path}"

    # Every video under site/media whose renditions aren't complete.
    def queue_missing!(force: false)
      return 0 unless available?

      originals.count { |path| queue!(web_path_for(path), force: force) }
    end

    # Videos in the Media Browser that need optimizing: never done (added
    # before ffmpeg was installed, or brought in by Site Sync or an import),
    # failed last time, or stuck — marked as working but with nothing queued
    # or running (an interrupted run, or the manifest bug that left
    # three-benches at 50%). Not ones genuinely busy, and not ones whose web
    # versions are complete.
    def needing_optimization
      busy = videos_with_jobs
      Medium.video.originals_only.select do |medium|
        next false unless File.file?(normalize_path(medium.file_path))
        next false if complete?(medium.file_path)

        case status_for(medium)[:state]
        when "failed", "none" then true
        when "optimizing"
          # Busy if Solid Queue has a job for it, it's reporting progress, or
          # it was queued within the last few hours (the dedup marker).
          !busy.include?(medium.file_path) &&
            Rails.cache.read(progress_key(medium.file_path)).nil? &&
            !Rails.cache.exist?(queue_cache_key(medium.file_path))
        else false
        end
      end
    end

    # Web paths with a transcode job waiting or running. Asks Solid Queue
    # directly; empty (so nothing counts as busy) with any other adapter.
    def videos_with_jobs
      return Set.new unless defined?(SolidQueue::Job) && ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

      SolidQueue::Job.where(class_name: "TranscodeVideoJob", finished_at: nil).filter_map do |job|
        Array(job.arguments.is_a?(Hash) ? job.arguments["arguments"] : nil).first
      end.to_set
    rescue => e
      Rails.logger.debug { "[VideoVariants] job check failed: #{e.message}" }
      Set.new
    end

    # The Media Browser's OPTIMIZE VIDEOS button: queue everything
    # needing_optimization lists. A failed video is retried — its error and
    # its queue marker are cleared first, or queue! would skip it. Returns
    # how many were queued.
    def optimize_all!
      return 0 unless available?

      needing_optimization.count do |medium|
        web = medium.file_path
        Rails.cache.delete(error_key(web))
        dequeue(web)
        set_status(web, "pending")
        queue!(web)
      end
    end

    def originals
      Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media", "**", "*"))
         .select { |p| File.file?(p) && video_file?(p) && !variant_path?(p) }
    end

    # ── Making one file ─────────────────────────────────────────────────

    # Make one rendition (or the poster) for a source. Returns the path
    # written, or nil when there was nothing to do (not needed for this
    # size, already there, or dropped because it wasn't smaller). Raises
    # Error with a plain-words message when it can't be made, or
    # StillArriving when the file is still being written.
    def generate(source, name, force: false)
      source = normalize_path(source)
      raise Error, "ffmpeg isn't installed." unless available?
      raise Error, "#{File.basename(source)} isn't there any more." unless File.file?(source)
      raise Error, "Refusing to make variants of a variant." if variant_path?(source)

      # A video copied in with Finder, or brought by Site Sync, is seen by
      # the file watcher as soon as it appears — long before a big file is
      # fully written. Reading it then fails; wait for it to settle instead.
      # Every job checks (a retried poster job goes to the back of the
      # queue, so a rendition job can come first), but only by size: a
      # finished upload is "just modified" too.
      if still_arriving?(source)
        raise StillArriving, "#{File.basename(source)} is still being copied in."
      end

      # One transcode at a time is Solid Queue's job (limits_concurrency),
      # but a retried job can slip past it — that's how two runs once
      # overlapped. This lock is the backstop: if another transcode holds
      # it, this job steps back and tries again shortly (Busy), rather than
      # running alongside or tying up a worker thread waiting.
      with_transcode_lock { generate_locked(source, name, force: force) }
    end

    def generate_locked(source, name, force:)
      probe = MediaProbe.call(source) or raise Error, "ffprobe couldn't read #{File.basename(source)}."
      raise Error, "#{File.basename(source)} has no video track." unless probe.video?

      manifest = fresh_manifest(source, probe)
      wanted = rendition_names_for(probe.short_side)
      manifest["wanted"] = wanted

      path =
        if name == POSTER
          make_poster(source, probe, manifest, force: force)
        elsif wanted.include?(name)
          make_rendition(source, name, probe, manifest, force: force)
        end

      finish(source, manifest, wanted, name)
      path
    ensure
      clear_progress(web_path_for(source)) if source
    end

    # Hold the one-transcode-at-a-time lock (a file in tmp/, shared by every
    # worker on this computer) for the block, or raise Busy straight away
    # if another transcode has it. One lock per environment, so the test
    # suite never waits on (or blocks) the development server's encodes.
    def with_transcode_lock
      dir = Rails.root.join("tmp", "video_variants")
      FileUtils.mkdir_p(dir)
      File.open(dir.join("transcode-#{Rails.env}.lock"), File::RDWR | File::CREAT, 0o644) do |lock|
        raise Busy, "Another video is being optimized." unless lock.flock(File::LOCK_EX | File::LOCK_NB)

        yield
      end
    end

    # Run ffmpeg the way every transcode runs: at low priority, with a
    # limited number of threads and a timeout. Output goes to a working
    # file outside site/ (Site Sync lists every file under site/, hidden
    # ones too, so a half-written rendition must never sit there) and is
    # moved into place only on success.
    #
    # on_progress, when given, is called with the number of seconds of video
    # encoded so far, read from ffmpeg's -progress output as it runs.
    def run_ffmpeg(args, output:, timeout:, on_progress: nil)
      FileUtils.mkdir_p(File.dirname(output))
      work_dir = Rails.root.join("tmp", "video_variants")
      FileUtils.mkdir_p(work_dir)
      partial = work_dir.join("#{SecureRandom.hex(6)}-#{File.basename(output)}").to_s

      cmd = []
      cmd += [ "nice", "-n", "10" ] if ManagedTools::Platform.find_executable("nice")
      cmd += [ tool.ffmpeg_path, "-nostdin", "-hide_banner", "-v", "error", "-y" ]
      cmd += [ "-progress", "pipe:1", "-nostats" ] if on_progress
      cmd += args + [ partial ]

      err, status = stream_ffmpeg(cmd, timeout: timeout, on_progress: on_progress)
      unless status&.success?
        reason = status ? err.lines.last.to_s.strip.presence || "ffmpeg stopped with an error" : "it took longer than #{timeout / 60} minutes"
        raise Error, "Couldn't make #{File.basename(output)}: #{reason}"
      end

      # mv rather than rename: tmp/ and site/ can be on different disks.
      FileUtils.mv(partial, output, force: true)
      output
    ensure
      FileUtils.rm_f(partial) if partial
    end

    # ── Status ──────────────────────────────────────────────────────────
    #
    # A video's Medium#variants_status moves through:
    #   pending     the column's default: nothing queued (no ffmpeg when it
    #               was added) — the original is served
    #   queued      jobs queued, nothing made yet
    #   processing  some files made, more to come
    #   ready       finished, and the Media Browser shows a notice about it
    #   complete    finished, notice dismissed
    #   failed      a step couldn't be done (notice shows why)
    #   failed_seen failed, notice dismissed
    # "ready" and "failed" are the ones the notice lists; DISMISSED maps each
    # to what it becomes once dismissed.
    NOTICE_STATUSES = %w[ready failed].freeze
    DISMISSED = { "ready" => "complete", "failed" => "failed_seen" }.freeze
    WORKING_STATUSES = [ nil, "pending", "queued", "processing" ].freeze

    def set_status(web_path, status)
      attrs = { variants_status: status }
      attrs[:variants_generated_at] = Time.current if status.in?(%w[ready complete])
      Medium.where(file_path: web_path).update_all(attrs)
    rescue => e
      Rails.logger.warn "[VideoVariants] Could not set status for #{web_path}: #{e.class}: #{e.message}"
    end

    # Clear the Media Browser's video notices (the Dismiss button).
    def dismiss_notices!
      DISMISSED.each { |from, to| Medium.video.where(variants_status: from).update_all(variants_status: to) }
    end

    def record_failure(web_path, message)
      set_status(web_path, "failed")
      Rails.cache.write(error_key(web_path), message.to_s, expires_in: 30.days)
    end

    def last_error(web_path) = Rails.cache.read(error_key(web_path))

    # ── Progress ────────────────────────────────────────────────────────
    #
    # While a file is being made, the job writes {step, percent} to the
    # cache (Solid Cache: shared by the worker and the web process). The
    # upload modal and the media card read it through status_for.

    def progress_key(web_path) = "video_progress:#{web_path}"
    def error_key(web_path) = "video_error:#{web_path}"

    def write_progress(web_path, step, percent)
      Rails.cache.write(progress_key(web_path), { "step" => step, "percent" => percent.to_i.clamp(0, 100) }, expires_in: 1.day)
    end

    def clear_progress(web_path) = Rails.cache.delete(progress_key(web_path))

    # Everything the Media Browser shows about one video's web versions:
    #   state     "optimizing", "done", "failed", or "none" (no ffmpeg and
    #             nothing made yet, so the original is served)
    #   percent   overall, across the renditions
    #   steps     [{ name, label, state: done|running|waiting|skipped|failed, percent }]
    #   source / outputs  sizes and dimensions, for the notice
    def status_for(medium)
      web = medium.file_path
      source = normalize_path(web)
      manifest = current_manifest(source)
      live = Rails.cache.read(progress_key(web))
      status = medium.variants_status

      # The database status is the authority on whether work is under way:
      # queue! sets "queued" before the jobs are enqueued, and only a
      # finished or failed run moves it on. (Earlier this was guessed from a
      # cache flag, which a job retrying cleared too soon — the progress
      # window then read "nothing happening" and stopped watching.)
      #
      # "Done" is different: it's decided by the files. A video marked
      # ready/complete whose web versions have since been deleted (by hand,
      # or lost) counts as not optimized, so OPTIMIZE VIDEOS offers it again
      # and the page stops pointing at files that aren't there.
      state =
        if status.in?(%w[failed failed_seen])
          "failed"
        elsif status.in?(%w[queued processing]) || live.present?
          "optimizing"
        elsif complete?(source)
          "done"
        else
          # Nothing queued and not complete: added before ffmpeg was
          # installed, its web versions were deleted, or a run was
          # interrupted. The original is served, along with whatever web
          # versions are left; OPTIMIZE VIDEOS catches it up.
          "none"
        end

      made = manifest ? Array(manifest["renditions"]).map { |r| r["name"] } : []
      skipped = manifest ? Array(manifest["skipped"]) : []
      wanted = manifest&.dig("wanted") || RENDITIONS.keys

      step_for = lambda do |name, done|
        step_state =
          if done then "done"
          elsif skipped.include?(name) then "skipped"
          elsif live && live["step"] == name then (state == "failed" ? "failed" : "running")
          else "waiting"
          end
        percent = { "done" => 100, "skipped" => 100, "running" => live&.dig("percent").to_i }[step_state] || 0
        { name: name, label: name == POSTER ? "poster" : name, state: step_state, percent: percent }
      end

      steps = [ step_for.(POSTER, manifest&.dig("poster").present?) ]
      wanted.each { |name| steps << step_for.(name, made.include?(name)) }

      renditions = steps.reject { |st| st[:name] == POSTER }
      percent = state == "done" ? 100 : (renditions.sum { |st| st[:percent] } / [ renditions.size, 1 ].max)

      {
        id: medium.id,
        name: File.basename(web),
        state: state,
        percent: percent,
        steps: steps,
        poster: (manifest["poster"] if manifest&.dig("poster") && File.file?(variant_path_for(source, POSTER))),
        source: manifest&.dig("source")&.slice("width", "height", "duration", "size") ||
                { "size" => (File.size(source) if File.file?(source)) },
        outputs: manifest ? Array(manifest["renditions"]).map { |r| r.slice("name", "size", "width", "height") } : [],
        served_as_original: manifest.present? && made.empty? && skipped.any?,
        error: (last_error(web) if state == "failed"),
        notice: status.in?(NOTICE_STATUSES)
      }
    end

    # Video Media rows the Media Browser notice should list.
    def notice_media = Medium.video.where(variants_status: NOTICE_STATUSES).order(:updated_at)

    # ── Cleanup ─────────────────────────────────────────────────────────

    # Remove every variant file of a source. Used when a video is deleted.
    def delete_variants(source)
      all_variant_paths(source).each { |p| FileUtils.rm_f(p) }
    end

    # Remove variant files whose original is gone. Returns how many.
    def prune_orphans!
      deleted = 0
      kept_elsewhere = stand_in_originals.to_set
      Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media", "**", "variants", "*#{MANIFEST_SUFFIX}")).each do |manifest|
        base = File.basename(manifest, MANIFEST_SUFFIX)
        dir = File.dirname(File.dirname(manifest))
        next if VIDEO_EXTENSIONS.any? { |ext| File.file?(File.join(dir, "#{base}#{ext}")) || File.file?(File.join(dir, "#{base}#{ext.upcase}")) }
        # On live, an original kept on the writing computer isn't gone.
        next if kept_elsewhere.include?(read_manifest_file(manifest)&.dig("source", "path"))

        all_variant_paths(File.join(dir, "#{base}.mp4")).each do |p|
          next unless File.file?(p)

          File.delete(p)
          deleted += 1
        end
      end
      deleted
    end

    private

    # Start from the manifest on disk if it belongs to this original.
    # Otherwise (first run, or the original was replaced) start fresh and
    # clear out the old variant files so they can't be mistaken for
    # current ones. `force` doesn't wipe anything here: each job rebuilds
    # only its own file, so a forced 720p job leaves the poster alone.
    def fresh_manifest(source, probe)
      existing = current_manifest(source)
      return existing if existing

      all_variant_paths(source).each { |p| FileUtils.rm_f(p) } if read_manifest(source)
      {
        "source" => {
          "path" => web_path_for(source), "size" => File.size(source),
          "width" => probe.width, "height" => probe.height,
          "duration" => probe.duration&.round(2), "codec" => probe.video_codec, "hdr" => probe.hdr?
        },
        "renditions" => [],
        "poster" => nil,
        "complete" => false
      }
    end

    def make_rendition(source, name, probe, manifest, force:)
      out = variant_path_for(source, name)
      return nil if !force && File.file?(out) && manifest["renditions"].any? { |r| r["name"] == name }

      ensure_disk_space!(source, out)
      web = web_path_for(source)
      write_progress(web, name, 0)
      duration = probe.duration.to_f
      last = 0.0
      reporter = lambda do |seconds|
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        next if now - last < 1 || duration <= 0

        last = now
        write_progress(web, name, seconds / duration * 100)
      end
      run_ffmpeg(encode_args(source, name, probe), output: out, timeout: timeout_for(probe), on_progress: reporter)

      if web_ready?(source, probe) && File.size(out) > File.size(source) * (1 - MIN_SAVING)
        # The original is already a small, web-friendly MP4 — the "web
        # version" would be about the same size or bigger. Serve the
        # original instead of keeping a near-copy.
        File.delete(out)
        manifest["renditions"].reject! { |r| r["name"] == name }
        manifest["skipped"] = (Array(manifest["skipped"]) | [ name ])
        return nil
      end

      made = MediaProbe.call(out)
      manifest["renditions"].reject! { |r| r["name"] == name }
      manifest["renditions"] << {
        "name" => name, "path" => web_path_for(out), "size" => File.size(out),
        "width" => made&.width, "height" => made&.height
      }
      out
    end

    def make_poster(source, probe, manifest, force:)
      out = variant_path_for(source, POSTER)
      return nil if !force && File.file?(out) && manifest["poster"]

      write_progress(web_path_for(source), POSTER, 0)
      at = poster_time(source, probe)
      short = [ probe.short_side.to_i, RENDITIONS.values.last[:short] ].min
      args = [ "-ss", format("%.2f", at), "-i", source, "-frames:v", "1",
               "-vf", video_filters(probe, short, frame_rate: nil), "-q:v", "3", "-map_metadata", "-1", "-f", "image2" ]
      run_ffmpeg(args, output: out, timeout: 120)
      manifest["poster"] = web_path_for(out)
      manifest["poster_at"] = at.round(2)
      out
    end

    # Seconds into the video to take the poster from. A few random points
    # in POSTER_RANGE are tried; the first that isn't (nearly) black wins,
    # else the brightest one seen. Very short clips use their middle.
    def poster_time(source, probe)
      duration = probe.duration.to_f
      return 0.0 if duration <= 0
      return duration / 2 if duration < 2

      candidates = Array.new(POSTER_TRIES) { rand(POSTER_RANGE) * duration }
      best = nil
      candidates.each do |at|
        brightness = frame_brightness(source, at)
        return at if brightness.nil? # can't measure: use it as it is
        return at if brightness >= POSTER_MIN_BRIGHTNESS

        best = [ at, brightness ] if best.nil? || brightness > best[1]
      end
      best[0]
    end

    # Average brightness (0–255) of the frame at `at` seconds, from a 16×16
    # greyscale thumbnail. nil if it couldn't be read.
    def frame_brightness(source, at)
      out, _err, status = ManagedTools::Platform.run(
        tool.ffmpeg_path, "-nostdin", "-v", "error", "-ss", format("%.2f", at), "-i", source,
        "-frames:v", "1", "-vf", "scale=16:16,format=gray", "-f", "rawvideo", "pipe:1",
        timeout: 30
      )
      return nil unless status&.success? && out.bytesize.positive?

      bytes = out.bytes
      bytes.sum / bytes.size
    rescue StandardError
      nil
    end

    # The settings that make the file small and quick to start:
    #   - H.264 high profile, 8-bit 4:2:0: plays on every browser and phone
    #   - CRF quality with a bitrate ceiling
    #   - +faststart: the index goes at the front, so playback starts
    #     before the whole file has downloaded
    #   - stereo AAC at 128k
    #   - no metadata, chapters or subtitles: drops the phone's location
    def encode_args(source, name, probe)
      spec = RENDITIONS.fetch(name)
      short = [ spec[:short], probe.short_side.to_i ].min
      [
        "-i", source,
        "-map", "0:v:0", "-map", "0:a:0?",
        "-vf", video_filters(probe, short, frame_rate: target_frame_rate(probe.frame_rate)),
        "-c:v", "libx264", "-preset", ENCODE[:preset], "-profile:v", "high",
        "-crf", spec[:crf].to_s, "-maxrate", spec[:maxrate], "-bufsize", spec[:bufsize],
        "-pix_fmt", "yuv420p",
        "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
        "-threads", encode_threads.to_s,
        "-c:a", "aac", "-b:a", ENCODE[:audio_bitrate], "-ac", "2",
        "-map_metadata", "-1", "-map_chapters", "-1", "-sn", "-dn",
        "-movflags", "+faststart",
        "-f", "mp4"
      ]
    end

    # Filters, in order: HDR → normal colour (when the source is HDR and
    # this ffmpeg can do it), resize by the shorter side to an even number
    # of pixels, frame-rate cap, 8-bit 4:2:0. ffmpeg has already applied the
    # phone's rotation flag by this point, so width/height are as displayed.
    def video_filters(probe, short, frame_rate:)
      short -= short % 2
      filters = []
      filters << hdr_to_sdr if probe.hdr? && tone_mapping?
      filters << (probe.width.to_i >= probe.height.to_i ? "scale=-2:#{short}" : "scale=#{short}:-2")
      filters << "fps=#{frame_rate}" if frame_rate
      filters << "format=yuv420p"
      filters.join(",")
    end

    def hdr_to_sdr
      "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv"
    end

    # zscale and tonemap are in most full ffmpeg builds (Homebrew, the
    # direct download, mise) but not every distro's. Without them an HDR
    # source still converts — it just looks a little washed out.
    def tone_mapping?
      @tone_mapping ||= {}
      @tone_mapping.fetch(tool.ffmpeg_path) do
        out, _err, status = ManagedTools::Platform.run(tool.ffmpeg_path, "-hide_banner", "-filters", timeout: 10)
        @tone_mapping[tool.ffmpeg_path] = status&.success? && out.match?(/\bzscale\b/) && out.match?(/\btonemap\b/)
      end
    end

    def web_ready?(source, probe)
      WEB_READY_EXTENSIONS.include?(File.extname(source).downcase) &&
        probe.video_codec == "h264" && probe.pixel_format == "yuv420p" && !probe.hdr?
    end

    # Growing while we watch — a copy or sync still writing it. Judged by
    # size alone: a finished upload also has a modified time of "just now",
    # and treating that as still-arriving sent every new upload's jobs off
    # to retry, out of order.
    def still_arriving?(source)
      size = File.size(source)
      sleep SETTLE_SECONDS
      File.size(source) != size
    rescue SystemCallError
      false
    end

    # Half the cores, so the site (and the rest of the computer) stays
    # responsive while a long video encodes.
    def encode_threads = [ Etc.nprocessors / 2, 1 ].max

    def timeout_for(probe)
      (probe.duration.to_f * 6).clamp(MIN_TIMEOUT, MAX_TIMEOUT).to_i
    end

    # Renditions are usually well under the original's size; need that much
    # free, plus a margin, before starting — both where ffmpeg writes
    # (tmp/) and where the file ends up (site/), which can be different
    # disks.
    def ensure_disk_space!(source, out)
      needed = File.size(source) + DISK_MARGIN
      [ Rails.root.join("tmp").to_s, File.dirname(out) ].uniq.each do |dir|
        free = free_bytes(dir)
        next if free.nil? || free >= needed

        raise Error, "Not enough free disk space to make #{File.basename(out)} " \
                     "(#{ActiveSupport::NumberHelper.number_to_human_size(free)} free, " \
                     "needs about #{ActiveSupport::NumberHelper.number_to_human_size(needed)})."
      end
    end

    def free_bytes(dir)
      FileUtils.mkdir_p(dir)
      out, _err, status = ManagedTools::Platform.run("df", "-Pk", dir, timeout: 10)
      return nil unless status&.success?

      kb = out.lines.last.to_s.split[3]
      kb&.match?(/\A\d+\z/) ? kb.to_i * 1024 : nil
    end

    # Write the manifest and update the Medium row. "complete" once the
    # poster and every needed rendition are done (a rendition dropped for
    # not being smaller counts as done).
    #
    # A job reads the manifest when it starts and finishes much later (a
    # long video's 1080p takes tens of minutes), so its copy can be stale.
    # Writing it back whole once lost another job's entry — a 720p made in
    # the meantime vanished from the manifest, leaving the video "stuck" at
    # 50%. So only this job's own step is taken from its copy and merged
    # into the manifest as it is now on disk, under a lock.
    def finish(source, manifest, wanted, name)
      path = manifest_path(source)
      FileUtils.mkdir_p(File.dirname(path))

      # The lock file lives in tmp/, not next to the manifest: Site Sync
      # lists every file under site/, and a stray .lock must never travel.
      lock_dir = Rails.root.join("tmp", "video_variants")
      FileUtils.mkdir_p(lock_dir)
      lock_path = lock_dir.join("#{Digest::SHA1.hexdigest(path)}.lock").to_s

      File.open(lock_path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        merged = merge_step(current_manifest(source), manifest, name)
        made = merged["renditions"].map { |r| r["name"] } | Array(merged["skipped"])
        merged["wanted"] = wanted
        merged["complete"] = merged["poster"].present? && (wanted - made).empty?
        merged["generated_at"] = Time.current.iso8601
        File.write(path, JSON.pretty_generate(merged) + "\n")
        manifest.replace(merged)
      end

      # Only a video that was being worked on becomes "ready" (and gets a
      # notice). Each job calls this, so a later job finding nothing left
      # to do mustn't bring back a notice that was already dismissed, or
      # paper over a step that failed.
      web = web_path_for(source)
      scope = Medium.where(file_path: web, variants_status: WORKING_STATUSES)
      if manifest["complete"]
        scope.update_all(variants_status: "ready", variants_generated_at: Time.current)
      else
        scope.update_all(variants_status: "processing")
      end
    rescue => e
      Rails.logger.warn "[VideoVariants] Could not record status for #{source}: #{e.class}: #{e.message}"
    end

    # The manifest on disk now (nil: none, or for a replaced original) with
    # this job's own step taken from its copy. Every other step stays as it
    # is on disk — that's what keeps a slower job from erasing a faster one.
    def merge_step(on_disk, mine, name)
      return mine.deep_dup if on_disk.nil?

      merged = on_disk.deep_dup
      if name == POSTER
        %w[poster poster_at].each { |k| merged[k] = mine[k] if mine.key?(k) }
      else
        merged["renditions"] = Array(merged["renditions"]).reject { |r| r["name"] == name } +
                               Array(mine["renditions"]).select { |r| r["name"] == name }
        merged["renditions"].sort_by! { |r| RENDITIONS.keys.index(r["name"]) || 99 }
        skipped = Array(merged["skipped"]) - [ name ]
        skipped << name if Array(mine["skipped"]).include?(name)
        merged["skipped"] = skipped if skipped.any? || merged.key?("skipped")
      end
      merged
    end

    # Run ffmpeg, reading its -progress output line by line. Returns
    # [stderr, Process::Status], or [stderr, nil] when it was killed for
    # running past `timeout`.
    def stream_ffmpeg(cmd, timeout:, on_progress:)
      Open3.popen3(*cmd) do |stdin, out, err, wait|
        stdin.close
        errors = Thread.new { err.read }
        reader = Thread.new do
          out.each_line do |line|
            key, value = line.strip.split("=", 2)
            next unless on_progress && key == "out_time_us" && value.to_s.match?(/\A\d+\z/)

            on_progress.call(value.to_i / 1_000_000.0)
          rescue => e
            Rails.logger.debug { "[VideoVariants] progress callback: #{e.message}" }
          end
        end

        status =
          if wait.join(timeout)
            wait.value
          else
            begin
              Process.kill("KILL", wait.pid)
            rescue Errno::ESRCH
              nil
            end
            wait.join
            nil
          end
        reader.join(2)
        errors.join(2)
        [ errors.value.to_s, status ]
      end
    end
  end
end
