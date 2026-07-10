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
      def reconcile(baseline:, local:, peer:)
        baseline ||= {}
        local    ||= {}
        peer     ||= {}

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
