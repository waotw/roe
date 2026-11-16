# frozen_string_literal: true

module SiteSync
  # Undo the newest sync: each side goes back to how its files were just
  # before it ran. What the sync sent to live goes back on live; what it
  # brought down goes back on local. The record of what both sides agreed on
  # goes back too, so the two sides are out of sync afterwards exactly as
  # they were, and the next sync makes the same changes again unless the
  # files are changed first.
  #
  # Only the newest sync that hasn't been rewound can be rewound
  # (`candidate`); rewinding an older one means rewinding each later one
  # first. Files only: the live database (members, sends, orders), secrets
  # and video originals are never touched.
  #
  # Every version a rewind replaces is saved first, the same as a sync
  # (Versions::Recorder), and the rewind is recorded as its own event.
  class Rewind
    class Error < StandardError; end
    class Unreachable < Error; end

    REWINDABLE = %w[sync push pull clone resolve].freeze
    PASSED_OVER = %w[rewind restore].freeze

    # One file to put back. `side` is :live or :local; `sha` nil = remove it.
    Step = Struct.new(:change, :side, :sha, :size, :mtime, :changed_since, :problem, keyword_init: true) do
      def path = change[:path]
      def remove? = sha.nil?
    end

    Plan = Struct.new(:event, :steps, keyword_init: true) do
      def live = steps.select { |s| s.side == :live && !s.problem }
      def local = steps.select { |s| s.side == :local && !s.problem }
      def changed_since = steps.select { |s| s.changed_since && !s.problem }
      def missing = steps.select { |s| s.problem == :no_copy }
      def remade = steps.select { |s| s.problem == :remade }
      def possible? = missing.empty? && (live.any? || local.any?)
    end

    class << self
      # The one event that can be rewound now: the newest sync not yet
      # rewound, provided it finished. Rewinds and restores in between don't
      # count. A sync that stopped partway can't be rewound, and nothing
      # before it can either.
      def candidate(events = Versions.events(limit: 200))
        events.each do |event|
          next if PASSED_OVER.include?(event[:kind]) || event[:rewound_by]
          return event if REWINDABLE.include?(event[:kind]) && event[:outcome] == "completed"

          return nil
        end
        nil
      end

      def rewindable?(event, events = Versions.events(limit: 200))
        event.present? && candidate(events)&.dig(:id) == event[:id]
      end

      # What rewinding `event` would do, given live's file list (`peer`, the
      # "files" map of Exchange.fetch_peer_manifest).
      def plan(event, peer:)
        baseline = Ledger.recorded&.dig("files") || {}
        hashes = {}
        steps = event[:changes].map { |change| step_for(change, event, peer, baseline, hashes) }
        Plan.new(event: event, steps: steps)
      end

      # Rewind `event`. Raises Unreachable before anything changes when live
      # can't be reached, and Error when the event isn't the one that can be
      # rewound or a saved version is missing.
      def perform!(event, on_step: nil, on_progress: nil)
        raise Error, "Only the newest sync can be rewound." unless rewindable?(event)

        peer = Exchange.fetch_peer_manifest
        raise Unreachable, "Couldn't reach the live site, so nothing was rewound. Try again when it's reachable." if peer.nil?

        plan = plan(event, peer: peer["files"] || {})
        if plan.missing.any?
          raise Error, "No saved copy of #{plan.missing.map(&:path).to_sentence}, so this sync can't be rewound."
        end
        raise Error, "Nothing to rewind: every file is already as it was before this sync." unless plan.possible?

        new(plan, peer["files"] || {}, on_step: on_step, on_progress: on_progress).call
      end

      private

      def step_for(change, event, peer, baseline, hashes)
        side = change[:direction] == "to_live" ? :live : :local
        step = Step.new(change: change, side: side, sha: change[:before_sha], size: change[:before_size])

        if !writable?(change[:path])
          step.problem = :not_ours
        elsif change[:action] != "added" && change[:before_sha].nil?
          # A version with nothing saved: a video web version, which backups
          # leave out because Roe makes it again from the original.
          step.problem = BackupPolicy.video_web_version?(change[:path]) ? :remade : :no_copy
        elsif change[:before_sha] && !Versions.object?(change[:before_sha])
          step.problem = :no_copy
        end

        step.mtime = change[:before_mtime] || fallback_mtime(change, event, side, peer)
        step.changed_since = changed_since?(change, side, peer, baseline, hashes)
        step
      end

      # Older records have no modified time. A time just before both the sync
      # and the other side's copy keeps the next sync reading the put-back
      # version as the older one, never as a newer edit.
      def fallback_mtime(change, event, side, peer)
        other =
          if side == :live
            abs = File.join(RoeSitePaths::SITE_PATH, change[:path])
            File.file?(abs) ? File.mtime(abs).to_i : nil
          else
            peer.dig(change[:path], "mtime")&.to_i
          end
        [ event[:at].to_i, other ].compact.min - 1
      end

      # Whether the side being rewound has changed this file since the sync,
      # so rewinding would replace that change too.
      def changed_since?(change, side, peer, baseline, hashes)
        rel = change[:path]
        if side == :local
          !VersionRestore.matches?(rel, change[:after_sha], size: change[:after_size], hashes: hashes)
        else
          now = peer[rel]
          return !now.nil? if change[:after_sha].nil?
          return true if now.nil?

          expected = change[:after_mtime] ? { "size" => change[:after_size], "mtime" => change[:after_mtime] } : baseline[rel]
          expected ? !Ledger.same_state?(now, expected) : now["size"].to_i != change[:after_size].to_i
        end
      end

      # A plain relative path inside /site that Site Sync may write.
      def writable?(rel)
        return false if rel.blank? || rel.include?("\0") || rel.start_with?("/")
        return false if Ledger.excluded?(rel)

        site = File.expand_path(RoeSitePaths::SITE_PATH)
        File.expand_path(File.join(site, rel)).start_with?(site + File::SEPARATOR)
      end
    end

    def initialize(plan, peer_files, on_step: nil, on_progress: nil)
      @plan = plan
      @peer_files = peer_files
      @on_step = on_step || ->(_) { }
      @on_progress = on_progress
      @recorder = Versions::Recorder.new
    end

    def call
      live = @plan.live
      local = @plan.local

      # What's there now is saved before anything is replaced. If it can't
      # be, nothing changes (Versions::SaveFailed).
      @on_step.call(:saving_versions)
      if live.any?
        paths = live.map(&:path)
        backup = SiteSync.transport.backup_live_to_local!(files: paths, on_progress: @on_progress)
        @recorder.save_live!(paths, from: backup, peer: @peer_files, deleted: live.select(&:remove?).map(&:path))
      end
      @recorder.save_local!(local.map(&:path), deleted: local.select(&:remove?).map(&:path)) if local.any?

      # Live first: it's the step that can fail on the network, and if it
      # does, local hasn't been touched.
      if live.any?
        @on_step.call(:rewinding_live)
        push_to_live!(live)
      end
      if local.any?
        @on_step.call(:rewinding_local)
        local.each { |step| write_local!(step) }
      end

      rewind_baseline!(live + local)
      @recorder.finish!(kind: :rewind, outcome: :completed, undoes: @plan.event[:id])
      settle!(live: live.any?, local: local.any?)
      Rails.logger.info "[SiteSync::Rewind] rewound event #{@plan.event[:id]}: #{live.size} on live, #{local.size} on local"
      @plan
    rescue Versions::SaveFailed
      raise
    rescue StandardError
      # Whatever was saved is still worth keeping.
      @recorder.finish!(kind: :rewind, outcome: :failed, undoes: @plan.event[:id])
      raise
    end

    private

    # The saved versions go to live from a folder laid out like /site, each
    # stamped with the time it had, so live holds exactly what it held.
    def push_to_live!(steps)
      staging = File.join(BackupPaths.root, "rewind", "#{Time.current.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(3)}")
      steps.reject(&:remove?).each do |step|
        dest = File.join(staging, step.path)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(Versions.object_path(step.sha), dest)
        File.utime(Time.at(step.mtime), Time.at(step.mtime), dest)
      end

      diff = { modified: [], added: steps.reject(&:remove?).map(&:path), deleted: steps.select(&:remove?).map(&:path) }
      SiteSync.transport.push_local_to_live!(diff: diff, on_progress: @on_progress, root: staging)
      steps.each do |step|
        @recorder.left_at(step.path, sha: step.sha, size: step.remove? ? nil : step.size, mtime: step.remove? ? nil : step.mtime)
      end
    ensure
      FileUtils.rm_rf(staging) if staging
    end

    def write_local!(step)
      abs = File.join(RoeSitePaths::SITE_PATH, step.path)
      if step.remove?
        File.delete(abs) if File.exist?(abs)
      else
        FileUtils.mkdir_p(File.dirname(abs))
        tmp = "#{abs}.roe-rewind-#{SecureRandom.hex(4)}"
        FileUtils.cp(Versions.object_path(step.sha), tmp)
        File.utime(Time.at(step.mtime), Time.at(step.mtime), tmp)
        File.rename(tmp, abs)
      end
    end

    # The agreed record goes back with the files: each path is recorded as
    # the version the rewound side now holds. The other side still has what
    # the sync left, so the next sync sees that side as the one that changed
    # and makes the same move again.
    #
    # Live's record goes back the same way (settle!), or live's own report
    # would say the opposite side changed.
    def rewind_baseline!(steps)
      @baseline_entries = steps.to_h { |step| [ step.path, step.remove? ? nil : { "size" => step.size, "mtime" => step.mtime } ] }
      Ledger.rewind_entries!(@baseline_entries)
    end

    def settle!(live:, local:)
      ContentSync.sync_all if local
      if live
        Exchange.reconcile_peer_content!
        Exchange.refresh_peer_ledger!
      end
      # After refresh_peer_ledger!, which keeps live's old entry for any path
      # the two sides hold differently: this replaces it with the rewound one.
      Exchange.rewind_peer_ledger!(@baseline_entries) if @baseline_entries.present?
      Checker.clear_cache
      Rails.cache.delete("site_sync:current_fingerprint")
      Exchange.call_peer if Exchange.can_call_peer?
    rescue StandardError => e
      # The files are back; a bookkeeping hiccup mustn't report a failure.
      Rails.logger.warn "[SiteSync::Rewind] settling after the rewind: #{e.class} #{e.message}"
    end
  end
end
