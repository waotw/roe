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
    Result = Struct.new(:in_sync, :differing, :confirmed_identical, keyword_init: true) do
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
          return Result.new(in_sync: false, differing: (structural + sized).sort, confirmed_identical: [])
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

        Result.new(in_sync: differing.empty?, differing: differing.sort, confirmed_identical: identical.sort)
      end
    end
  end
end
