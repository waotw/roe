# frozen_string_literal: true

module SiteSync
  # Which video files stay on this computer instead of going to the live
  # site. One setting in site.yml, `sync_live_video`:
  #
  #   1080p    (default) the web versions go to live; the original stays here
  #   720p     only the 720p web version (and the poster) goes to live
  #   original everything goes to live, as before
  #
  # Live pages never serve an original once a video has web versions — the
  # player plays the 720p first and the 1080p second, and the download link
  # points at what's played — so on live an original is dead weight, often
  # the biggest file on the disk. This computer always keeps every file.
  #
  # A file is held back only when what live would play in its place exists
  # here: an original once it has a web version, the 1080p once there's a
  # 720p. A video without web versions (added on a computer without ffmpeg,
  # or whose encode failed) sends its original, because that's all there is
  # to play. One whose web versions are being made right now waits for them.
  #
  # How Site Sync treats a held-back file, the same way it treats Roe's
  # documentation set to `local` (Ledger.roe_docs_path?):
  #
  #   - it's left out of this computer's manifest, and dropped from live's
  #     manifest and the baseline when they're compared, so it's never a
  #     push, a pull, a deletion or a difference to warn about;
  #   - every push carries the list, and live deletes any it still has.
  #     That's how live's copies go once the setting is chosen. It's safe
  #     because the list is made from files this computer has, and it's
  #     quiet for the same reason: nothing is lost.
  #
  # Live never holds anything back itself (live_side?): its manifest reports
  # what it has, so this computer can see what to remove, and it accepts any
  # file it's sent, so changing the setting back to `original` sends the
  # originals again. On live, a video whose original isn't there is kept
  # alive by its -video.json (VideoVariantGenerator.stand_in_originals).
  # Nothing is held back until live has said it can do that (peer_ready?).
  module LiveVideo
    module_function

    SETTING = "sync_live_video"
    CHOICES = %w[1080p 720p original].freeze
    DEFAULT = "1080p"

    # Recomputed at most this often. Ledger.excluded? asks about every file
    # under /site during a manifest walk, and the answer reads each video's
    # -video.json; within one walk it can't change.
    CACHE_SECONDS = 5

    def choice
      value = SiteConfig.get(SETTING).to_s.strip.downcase
      CHOICES.include?(value) ? value : DEFAULT
    rescue StandardError
      DEFAULT # a config read must never stop a sync
    end

    # The live site keeps whatever it's sent and holds nothing back.
    def live_side? = Rails.env.production?

    # Can the live site run a video without its original? A live site on an
    # older Roe can't: it would see the original missing, drop the video's
    # record, and delete its web versions with it — so until live says it
    # can, nothing is held back and everything is sent, as before.
    #
    # Live says so in its manifest reply (Api::SiteSync::ExchangeController
    # #manifest), and every sync fetches that before deciding anything;
    # Exchange.fetch_peer_manifest records the answer here.
    PEER_READY_CACHE_KEY = "site_sync:peer_keeps_videos_without_originals"

    def peer_ready? = Rails.cache.read(PEER_READY_CACHE_KEY) == true

    def record_peer_ready!(ready)
      ready = ready == true
      return if Rails.cache.read(PEER_READY_CACHE_KEY) == ready

      Rails.cache.write(PEER_READY_CACHE_KEY, ready, expires_in: 30.days)
      reset_cache!
    end

    def held_back?(relative_path)
      held_back_paths.include?(relative_path.to_s.delete_prefix("/"))
    end

    # Paths relative to /site ("media/video/clip.mov"), each a file on this
    # computer. Empty on live, and when the setting is `original`.
    def held_back_paths = computed[:held]

    # What every push asks live to delete: the held-back files whose
    # replacement is already here. Live deletes the ones it has and ignores
    # the rest, so sending the whole list each time is cheap and does
    # nothing once live is tidy.
    #
    # An original held back only because its web versions are being made
    # isn't on the list: live may be playing that very file (a video sent
    # before ffmpeg was installed) until the web versions reach it.
    def to_purge = computed[:purge].to_a.sort

    def computed
      if @computed_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) - @computed_at < CACHE_SECONDS
        return @computed
      end

      @computed = compute
      @computed_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @computed
    end

    def reset_cache!
      @computed_at = nil
      @computed = nil
    end

    # rsync --exclude rules for the held-back files, anchored at /site so a
    # name can't match elsewhere. The rsync transports add these to a full
    # push (so the files aren't sent), a full pull and a live backup (so
    # --delete never removes this computer's copies, and live's aren't
    # downloaded). Shell-quoted, because the transports join their excludes
    # into one command line; wildcard characters are backslashed so rsync
    # reads each as a plain name.
    def rsync_exclude_args
      held_back_paths.sort.map do |rel|
        pattern = "/" + rel.gsub(/([*?\[\]\\])/) { "\\#{::Regexp.last_match(1)}" }
        "--exclude=#{Shellwords.escape(pattern)}"
      end
    end

    EMPTY = { held: Set.new.freeze, purge: Set.new.freeze }.freeze

    def compute
      return EMPTY if live_side?
      return EMPTY unless peer_ready?

      wanted = choice
      return EMPTY if wanted == "original"

      # Originals whose web versions are queued or being made right now.
      # Held back too: a sync during the encode would otherwise send the
      # whole original only for the next sync to remove it. If the encode
      # fails the status says so, and the original goes as usual.
      busy = Medium.video.where(variants_status: %w[queued processing]).pluck(:file_path).to_set

      held = Set.new
      purge = Set.new
      VideoVariantGenerator.originals.each do |source|
        original = relative(source)
        names = VideoVariantGenerator.available_renditions(source).map { |r| r["name"] }
        # What live plays in the original's place, at this setting.
        replaced = wanted == "720p" ? names.include?("720p") : names.any?

        if replaced
          held << original
          purge << original
          bigger = VideoVariantGenerator.variant_path_for(source, "1080p")
          if wanted == "720p" && names.include?("1080p") && File.file?(bigger)
            held << relative(bigger)
            purge << relative(bigger)
          end
        elsif busy.include?(VideoVariantGenerator.web_path_for(source))
          held << original # waits for its web versions; not purged
        end
      end
      { held: held, purge: purge }
    rescue StandardError => e
      # Holding back nothing sends more than wanted; guessing wrong the other
      # way could stop a video reaching live. So on any error, send it all.
      Rails.logger.warn "[SiteSync::LiveVideo] couldn't work out which videos to keep here: #{e.class} #{e.message}"
      EMPTY
    end

    def relative(absolute)
      absolute.to_s.delete_prefix("#{RoeSitePaths::SITE_PATH.to_s.chomp('/')}/")
    end
  end
end
