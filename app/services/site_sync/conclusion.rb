# frozen_string_literal: true

module SiteSync
  # One answer to "are we and the peer holding the same content", for every
  # surface that asks — the admin banner, the nav dot, the imports publish
  # panel, and the Site Sync page.
  #
  # Each of those computed `local_fp == peer_fp` on its own, and only the Site
  # Sync page also consulted PeerAgreement when they differed. So the page could
  # say "in sync" while the banner said "differs" on the same render, because
  # the page had a second opinion the banner never asked for.
  #
  # The third state is the point. Peer data is cached and deliberately allowed
  # to go stale — refresh_if_stale hands back what's in the cache and refreshes
  # in the background — so comparing a freshly walked local fingerprint against
  # a peer answer recorded before our last sync reports drift on a sync that
  # worked. When the peer's answer predates our own last change we don't know,
  # and saying so beats saying something wrong.
  Conclusion = Struct.new(:state, :as_of, :local_fingerprint, :peer_fingerprint,
                          :agreement, :peer_reachable, :configured, :last_synced_at,
                          keyword_init: true) do
    # refresh: true enqueues Exchange's background ping when the cached peer
    # state is old. The Site Sync page passes the state it already read.
    def self.current(refresh: true, peer_state: nil)
      configured = Exchange.can_call_peer?
      state      = peer_state || (refresh ? Exchange.refresh_if_stale : Exchange.peer_state) rescue nil
      local      = (Ledger.fingerprint_for(RoeSitePaths::SITE_PATH) rescue nil)
      recorded   = (Ledger.recorded&.dig("version") rescue nil)
      synced_at  = (Time.parse(recorded.to_s) if recorded.present?) rescue nil

      base = {
        as_of: state&.dig(:received_at), local_fingerprint: local,
        peer_fingerprint: state&.dig(:fingerprint), configured: configured,
        peer_reachable: Exchange.peer_reachable?, last_synced_at: synced_at
      }

      # Nothing to compare against, or nothing recent enough to compare with.
      return new(state: :unknown, **base) if !configured || base[:local_fingerprint].blank? ||
                                             base[:peer_fingerprint].blank?
      return new(state: :unknown, **base) if synced_at && base[:as_of] && base[:as_of] < synced_at

      return new(state: :in_sync, **base) if local == base[:peer_fingerprint]

      # The fingerprint covers size + mtime, so identical bytes with a different
      # timestamp read as a difference — and warn about drift a sync can't
      # clear, because there's nothing to transfer. Confirm the bytes before
      # believing it. Only the differing paths get hashed, and only here.
      agreement = PeerAgreement.verify(local_fingerprint: local,
                                       peer_fingerprint: base[:peer_fingerprint])

      new(state: agreement&.in_sync ? :in_sync : :out_of_sync, agreement: agreement, **base)
    end

    def in_sync?     = state == :in_sync
    def out_of_sync? = state == :out_of_sync
    def unknown?     = state == :unknown

    # True when the peer is set up but we can't currently say anything about it
    # — the case worth explaining on the Site Sync page rather than nagging
    # about in the banner.
    def undecided? = unknown? && configured
  end
end
