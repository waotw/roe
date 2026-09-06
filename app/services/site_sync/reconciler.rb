require "digest"

module SiteSync
  # Three-way reconciliation for bi-directional Site Sync. Compares the
  # last-synced baseline (the local ledger) against the current local and
  # peer manifests and classifies every path as a safe one-way
  # propagation or a genuine conflict — both sides diverged from the
  # baseline in different ways. Conflicts block the sync until resolved;
  # nothing is ever silently overwritten.
  #
  # "Changed" is size+mtime (what the ledger already tracks). An
  # edit/edit pair whose sizes match but mtimes differ is only a
  # *candidate* — cross-machine mtime skew is common — and is confirmed by
  # content hash before it's called a real conflict (see .confirm).
  class Reconciler
    # A genuine conflict. `type` is one of the constants below; `local`
    # and `peer` are the {size,mtime} entries (nil = absent on that side).
    Conflict = Struct.new(:path, :type, :local, :peer, keyword_init: true)

    # How many deletions a sync may apply without asking. Set in site.yml as
    # `sync_confirm_deletions_over`; this is the fallback when it's unset.
    #
    # Deleting in Roe is deliberate — you delete a post, you meant it — so
    # propagating that needs no ceremony, and a prompt on every routine delete
    # would just train people to click through. But a sync that proposes thirty
    # deletions has misread something, and nobody deletes thirty files by hand
    # without noticing.
    #
    # 0 by default: confirm everything. That's the safe end of the dial, and
    # it's where a new install should start — after a sync destroyed 9 episodes
    # and 23 audio files on 2026-08-26 by inferring a deletion that never
    # happened, the case for a cautious default makes itself.
    #
    #   0   → confirm every deletion (default)
    #   20  → confirm only bulk deletions
    #   nil → never confirm, propagate deletions silently
    DEFAULT_CONFIRM_DELETIONS_OVER = 0

    EDIT_EDIT   = :edit_edit     # both sides edited, content differs
    EDIT_DELETE = :edit_delete   # edited locally, deleted on the peer
    DELETE_EDIT = :delete_edit   # deleted locally, edited on the peer

    # The classification. push/pull are add-or-modify propagations;
    # *_delete are deletions to propagate; converged = both sides made the
    # same change (no transfer, just re-baseline); conflicts need
    # resolution.
    Result = Struct.new(:push, :push_delete, :pull, :pull_delete, :conflicts, :converged, keyword_init: true) do
      def any_conflicts?
        conflicts.any?
      end
    end

    class << self
      # Read per-sync rather than memoized: someone changing the setting
      # expects the next sync to use it, not the next boot.
      #
      # A blank setting means "unset" and falls back. An explicit 0 does not —
      # `to_i` would flatten both to 0, which happens to be the default today
      # but would quietly mean "confirm everything" if the default ever moved.
      def confirm_deletions_over
        raw = SiteConfig.get("sync_confirm_deletions_over")
        return DEFAULT_CONFIRM_DELETIONS_OVER if raw.nil? || raw.to_s.strip.empty?
        return nil if raw.to_s.strip.downcase.in?(%w[never off none])

        Integer(raw, exception: false) || DEFAULT_CONFIRM_DELETIONS_OVER
      end

      def reconcile(baseline:, local:, peer:)
        baseline ||= {}
        local    ||= {}
        peer     ||= {}

        # Roe's own docs, when this side is set to keep them local, are out of
        # scope rather than deleted. They're excluded from our manifest, so
        # their absence would otherwise read as us deleting them and ask before
        # propagating — 113 files to confirm, for a setting the user just chose
        # deliberately. Excluding them here means no push, no pull, no conflict;
        # HttpTransport removes live's copies quietly on the next push.
        #
        # Safe to be silent about only because these ship with Roe: they're
        # always on this computer, and turning the setting back on restores them.
        if SiteSync::Ledger.roe_docs_excluded?
          baseline = baseline.reject { |path, _| SiteSync::Ledger.roe_docs_path?(path) }
          local    = local.reject    { |path, _| SiteSync::Ledger.roe_docs_path?(path) }
          peer     = peer.reject     { |path, _| SiteSync::Ledger.roe_docs_path?(path) }
        end

        push = []; push_delete = []; pull = []; pull_delete = []; conflicts = []; converged = []

        (baseline.keys | local.keys | peer.keys).each do |path|
          b = baseline[path]
          l = local[path]
          p = peer[path]
          local_changed = !same?(l, b)
          peer_changed  = !same?(p, b)
          next unless local_changed || peer_changed

          if local_changed && !peer_changed
            (l ? push : push_delete) << path
          elsif peer_changed && !local_changed
            (p ? pull : pull_delete) << path
          elsif same?(l, p)
            converged << path # both sides landed on the same state
          else
            conflicts << classify_conflict(path, l, p)
          end
        end

        Result.new(
          push:        push.sort,
          push_delete: push_delete.sort,
          pull:        pull.sort,
          pull_delete: pull_delete.sort,
          conflicts:   conflicts.sort_by(&:path),
          converged:   converged.sort
        )
      end

      # Turn every planned deletion into a conflict the admin has to confirm.
      #
      # A deletion is the only propagation that destroys something, and it is
      # *inferred*, not observed. "Absent on the peer, present in the baseline"
      # is a guess that the peer deleted it — and the guess is only as good as
      # the baseline. When a file reaches the baseline without ever reaching
      # the peer, the peer's absence is read as a deletion that never happened,
      # and the file is destroyed on the only side that had it. That is exactly
      # how 9 episodes and 23 audio files were lost on 2026-08-26: nothing was
      # deleted on live, because live never had them.
      #
      # The baseline fix keeps un-transferred files out. This is the net under
      # it: even with a wrong baseline, a deletion now has to be confirmed.
      #
      # The existing conflict types already carry the right semantics:
      #
      #   pull_delete (gone on the peer, still here) → edit_delete
      #     keep mine = push it back, keep live = accept the deletion
      #   push_delete (deleted here, still on the peer) → delete_edit
      #     keep mine = propagate my delete, keep live = restore it
      #
      # so build_plan, the resolution job and the UI handle these without
      # knowing they came from here.
      def require_delete_confirmation(result, baseline:, local:, peer:)
        planned = result.pull_delete.size + result.push_delete.size
        threshold = confirm_deletions_over
        return result if threshold.nil?
        return result if planned <= threshold

        extra = result.pull_delete.map do |path|
          Conflict.new(path: path, type: EDIT_DELETE, local: local[path], peer: nil)
        end + result.push_delete.map do |path|
          Conflict.new(path: path, type: DELETE_EDIT, local: nil, peer: peer[path])
        end

        return result if extra.empty?

        Result.new(
          push:        result.push,
          push_delete: [],
          pull:        result.pull,
          pull_delete: [],
          conflicts:   (result.conflicts + extra).sort_by(&:path),
          converged:   result.converged
        )
      end

      # The subset of conflicts worth a content-hash round trip: edit/edit
      # pairs whose sizes match (so content *might* be identical despite an
      # mtime difference). A size mismatch already proves the content
      # differs, so those stay conflicts without a hash check.
      def hash_candidates(result)
        result.conflicts
              .select { |c| c.type == EDIT_EDIT && c.local && c.peer && c.local["size"] == c.peer["size"] }
              .map(&:path)
      end

      # Reclassify candidates using content hashes: a candidate whose local
      # and peer content actually match is not a conflict (mtime skew) →
      # move it to `converged`. Requires both hashes to be present, so a
      # path we didn't hash stays a conflict. Returns a new Result.
      def confirm(result, local_hashes:, peer_hashes:)
        real = []
        converged = result.converged.dup

        result.conflicts.each do |c|
          lh = local_hashes[c.path]
          ph = peer_hashes[c.path]
          if c.type == EDIT_EDIT && lh && ph && lh == ph
            converged << c.path
          else
            real << c
          end
        end

        Result.new(
          push:        result.push,
          push_delete: result.push_delete,
          pull:        result.pull,
          pull_delete: result.pull_delete,
          conflicts:   real,
          converged:   converged.sort
        )
      end

      # SHA256 of each path's content, relative to `root`. Missing files are
      # skipped. Used on each side (the peer via the file_hashes endpoint,
      # locally by the reconcile flow) to confirm real conflicts.
      def hashes_for(paths, root: RoeSitePaths::SITE_PATH)
        Array(paths).each_with_object({}) do |rel, acc|
          full = File.join(root, rel.to_s)
          next unless File.file?(full)
          acc[rel.to_s] = Digest::SHA256.file(full).hexdigest
        rescue => e
          Rails.logger.warn "[SiteSync::Reconciler] hash failed for #{rel}: #{e.message}"
        end
      end

      private

      # Two {size,mtime} entries (or nils) represent the same state?
      def same?(a, b)
        return true if a.nil? && b.nil?
        return false if a.nil? || b.nil?
        a["size"] == b["size"] && a["mtime"] == b["mtime"]
      end

      def classify_conflict(path, local, peer)
        type = if local && peer
          EDIT_EDIT
        elsif local
          EDIT_DELETE
        else
          DELETE_EDIT
        end
        Conflict.new(path: path, type: type, local: local, peer: peer)
      end
    end
  end
end
