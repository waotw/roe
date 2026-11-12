# frozen_string_literal: true

module SiteSync
  # Answers "are local and live actually holding the same content?" when the
  # cheap fingerprint check says they aren't.
  #
  # The fingerprint is a SHA of `{path => {size, mtime}}`, so a file with
  # identical bytes and a different timestamp counts as a difference. That
  # produced a warning the user couldn't clear:
  #
  #   "Content differs from Live site, but neither side reports drift —
  #    a sync will realign them."
  #
  # A sync can't realign them. With no drift on either side the reconciler has
  # nothing to transfer, so nothing rewrites those mtimes and the warning
  # stands forever.
  #
  # Reconciler already draws this distinction for conflicts — hash_candidates
  # narrows by size, confirm() round-trips SHAs and reclassifies mtime skew as
  # converged. This applies the same idea one level up, to the status check.
  #
  # Only runs when the fingerprints already disagree, and only hashes the paths
  # that differ — typically a handful out of several hundred. The in-sync path
  # stays a single fingerprint comparison and costs nothing extra.
  class PeerAgreement
    # `on_live` / `on_local`: the differing files this computer's sync record
    # can place on one side, as { modified:, added:, deleted: }. Each side's
    # own record can miss a change the other side's caught — a rewind puts
    # this computer's record back but not live's — and this record is the one
    # a sync goes by (Reconciler). Files neither record explains stay in
    # `differing`.
    Result = Struct.new(:in_sync, :differing, :confirmed_identical, :on_live, :on_local, keyword_init: true) do
      def mtime_only? = in_sync && confirmed_identical.to_a.any?
    end

    CACHE_TTL = 30.seconds

    class << self
      # nil when the peer can't be reached — the caller keeps whatever the
      # fingerprint comparison said rather than guessing.
      def verify(local_fingerprint:, peer_fingerprint:)
        return nil if local_fingerprint.blank? || peer_fingerprint.blank?

        Rails.cache.fetch(cache_key(local_fingerprint, peer_fingerprint), expires_in: CACHE_TTL) do
          compare
        end
      rescue StandardError => e
        Rails.logger.warn "[SiteSync::PeerAgreement] #{e.class}: #{e.message}"
        nil
      end

      private

      def cache_key(local_fp, peer_fp) = "site_sync:agreement:#{local_fp}:#{peer_fp}"

      def compare
        peer = Exchange.fetch_peer_manifest
        return nil if peer.nil?

        local      = Ledger.current
        peer_files = peer["files"] || {}

        # A path on one side only, or a size difference, already proves the
        # content differs. No point hashing.
        structural = (local.keys - peer_files.keys) | (peer_files.keys - local.keys)
        shared     = local.keys & peer_files.keys
        sized      = shared.select { |p| local[p]["size"].to_i != peer_files[p]["size"].to_i }

        if structural.any? || sized.any?
          return explained(Result.new(in_sync: false, differing: (structural + sized).sort, confirmed_identical: []), local, peer_files)
        end

        candidates = shared.select { |p| local[p]["mtime"].to_i != peer_files[p]["mtime"].to_i }
        return Result.new(in_sync: true, differing: [], confirmed_identical: []) if candidates.empty?

        local_hashes = Reconciler.hashes_for(candidates)
        peer_hashes  = Exchange.fetch_peer_file_hashes(candidates)

        identical, differing = candidates.partition do |path|
          lh = local_hashes[path]
          ph = peer_hashes[path]
          # A hash we couldn't get counts as differing. Being wrong towards
          # "check this" is recoverable; claiming a sync that didn't happen
          # isn't.
          lh.present? && ph.present? && lh == ph
        end

        explained(Result.new(in_sync: differing.empty?, differing: differing.sort, confirmed_identical: identical.sort), local, peer_files)
      end

      # Sort each differing file by which side changed it since the last
      # agreed record, as the next sync will.
      def explained(result, local, peer_files)
        # No record yet (a first sync): nothing to place them by.
        baseline = Ledger.recorded&.dig("files")
        return result if baseline.nil?

        on_live  = { modified: [], added: [], deleted: [] }
        on_local = { modified: [], added: [], deleted: [] }
        rest = []
        result.differing.each do |path|
          was = baseline[path]
          live_changed  = !same?(peer_files[path], was)
          local_changed = !same?(local[path], was)
          if live_changed && !local_changed
            on_live[change_kind(was, peer_files[path])] << path
          elsif local_changed && !live_changed
            on_local[change_kind(was, local[path])] << path
          else
            rest << path
          end
        end
        result.on_live  = on_live  if on_live.values.any?(&:any?)
        result.on_local = on_local if on_local.values.any?(&:any?)
        result.differing = rest
        result
      end

      def same?(a, b) = (a.nil? && b.nil?) || Ledger.same_state?(a, b)

      def change_kind(was, now)
        return :added if was.nil?
        return :deleted if now.nil?

        :modified
      end
    end
  end
end
