require 'net/http'
require 'json'

module SiteSync
  # Cross-environment state exchange. The communication is
  # asymmetric because dev (laptop, NAT, intermittent) can't host
  # an endpoint prod can call. So:
  #
  #   - Dev INITIATES the exchange. It POSTs its local state to
  #     prod and reads prod's state from the response.
  #   - Prod RECEIVES exchanges. Whenever dev calls in, prod stores
  #     dev's state in its cache, returns its own.
  #
  # Both sides cache the peer's last-known state under the same
  # cache key (`site_sync:peer_state`). Each side only ever has
  # one peer (the other env), so a single key suffices.
  #
  # Configuration lives in the singleton `SyncConfig` model (one row
  # in the primary DB). Editable via the admin Site Sync page:
  #
  #   token     — random shared secret, must match both sides
  #   peer_url  — only used on dev (prod doesn't initiate)
  #
  # On prod the peer_url is unused; we gate outbound calls by
  # Rails.env so an accidentally-set value doesn't make prod try to
  # phone home to itself.
  class Exchange
    PEER_STATE_CACHE_KEY  = "site_sync:peer_state".freeze
    PEER_STATE_TTL        = 1.day            # stop trusting peer state after this
    REFRESH_STALE_AFTER   = 60.seconds       # threshold for opportunistic refresh
    HTTP_TIMEOUT_SECONDS  = 5

    # Cap for the per-category drift file list we ship in the
    # exchange payload. A pathological case (e.g. a fresh push that
    # touched every file) could otherwise produce a multi-MB JSON
    # body. The full counts are still sent; only the path arrays
    # get truncated.
    DRIFT_LIST_CAP        = 500

    class << self
      # State payload describing THIS environment, used both as the
      # body of outbound exchange calls and as the response to
      # inbound ones. `version` is just a timestamp, included so the
      # peer can tell when this snapshot was taken. `drift` is the
      # file-level diff against this side's last-recorded baseline,
      # so the peer's UI can show which files changed instead of
      # just a count.
      def local_state
        current_files = SiteSync::Ledger.current
        recorded      = SiteSync::Ledger.recorded
        recorded_files = recorded&.dig('files') || {}

        state = {
          fingerprint:          SiteSync::Ledger.fingerprint_of(current_files),
          recorded_fingerprint: recorded&.dig('fingerprint'),
          env:                  Rails.env.to_s,
          version:              Time.now.utc.iso8601
        }

        if recorded
          diff = SiteSync::Ledger.diff(current_files, recorded_files)
          state[:drift] = build_drift_payload(diff)
        end

        state
      end

      # Inbound: peer just sent us their state. Cache it and return
      # ours so they can update their own peer cache from the
      # response. Single round trip carries info both ways.
      def handle_inbound(payload)
        save_peer_state(payload)
        local_state
      end

      # Outbound: send our state to the peer, store theirs. Returns
      # the peer's state on success, nil on failure (network error,
      # auth failure, malformed response, etc.). Failures are logged
      # but never raised — exchange is best-effort.
      def call_peer
        return nil unless can_call_peer?

        uri = URI.parse(File.join(peer_url, '/api/site_sync/exchange'))

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == 'https')
        http.read_timeout = HTTP_TIMEOUT_SECONDS
        http.open_timeout = HTTP_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type']  = 'application/json'
        request['Authorization'] = "Bearer #{token}"
        request.body             = local_state.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn "[SiteSync::Exchange] peer responded #{response.code}: #{response.body}"
          return nil
        end

        parsed = JSON.parse(response.body)
        save_peer_state(parsed)
        parsed
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] peer call failed: #{e.class} #{e.message}"
        nil
      end

      # Tell the peer to walk its own /site and rewrite its ledger
      # to match. Called after a push so the peer's drift detection
      # doesn't claim "everything changed" from the rsync touching
      # mtimes on every transferred file. Returns true on success,
      # false on any failure (best-effort — failures are logged but
      # don't fail the calling job).
      #
      # This is push-only — pull doesn't need it because the local
      # job already updates the local ledger, and the peer's /site
      # didn't change.
      def refresh_peer_ledger!
        return false unless can_call_peer?

        uri = URI.parse(File.join(peer_url, '/api/site_sync/refresh_ledger'))

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == 'https')
        # Walking /site can take a few seconds on a 2GB tree; give
        # it more headroom than a regular exchange call.
        http.read_timeout = 30
        http.open_timeout = HTTP_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request['Content-Type']  = 'application/json'
        request['Authorization'] = "Bearer #{token}"
        request.body             = '{}'

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn "[SiteSync::Exchange] refresh_peer_ledger got #{response.code}: #{response.body}"
          return false
        end

        true
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] refresh_peer_ledger failed: #{e.class} #{e.message}"
        false
      end

      # Cached peer state from the most recent exchange (inbound or
      # outbound). Returns nil if we've never spoken to the peer or
      # the cache entry has expired.
      def peer_state
        Rails.cache.read(PEER_STATE_CACHE_KEY)
      end

      # Read peer state, but trigger a background refresh if it's
      # stale. The current request gets whatever's in cache (possibly
      # stale or nil); a Solid Queue job runs `call_peer` async so
      # the next render sees fresh data. Threading the HTTP call
      # into the request cycle directly would block the page render
      # — and would fail badly when the peer is unreachable.
      def refresh_if_stale
        state = peer_state
        if state.nil? || state[:received_at].to_i < REFRESH_STALE_AFTER.ago.to_i
          SiteSyncExchangeJob.perform_later if can_call_peer?
        end
        state
      end

      # True if peer reports unsynced changes (their current
      # fingerprint differs from their recorded baseline). nil
      # `recorded_fingerprint` means no baseline established yet,
      # which we treat as "not drift" to match Checker's behavior.
      def peer_has_drift?
        state = peer_state
        return false unless state
        return false if state[:recorded_fingerprint].nil?
        state[:fingerprint] != state[:recorded_fingerprint]
      end

      # Human label for the peer's environment. Used in the banner
      # so it reads naturally regardless of which side we're on.
      def peer_label
        case peer_state&.dig(:env)
        when 'production'  then 'Live site'
        when 'development' then 'Local site'
        else                    peer_state&.dig(:env)&.to_s&.capitalize
        end
      end

      # When did we last hear from the peer? Used for the debug
      # panel; nil if no contact yet.
      def last_contact_at
        peer_state&.dig(:received_at)
      end

      def can_call_peer?
        peer_url.present? && token.present?
      end

      def peer_url
        # Production never initiates — gate by env so a stray
        # peer_url in the SyncConfig row doesn't make prod try to
        # phone something. (The form hides the field on prod, but
        # this is defense in depth.)
        return nil unless Rails.env.development?
        SyncConfig.current.peer_url.presence
      rescue ActiveRecord::StatementInvalid
        # Table doesn't exist yet (migration pending). Treat as
        # unconfigured rather than crash the admin layout.
        nil
      end

      def token
        SyncConfig.current.token
      rescue ActiveRecord::StatementInvalid
        nil
      end

      private

      # Symbolize keys defensively — JSON.parse returns string keys,
      # but `local_state` builds a symbol-keyed hash, so callers
      # can rely on either path producing the same shape.
      def save_peer_state(payload)
        normalized = {
          fingerprint:          payload['fingerprint']          || payload[:fingerprint],
          recorded_fingerprint: payload['recorded_fingerprint'] || payload[:recorded_fingerprint],
          env:                  payload['env']                  || payload[:env],
          version:              payload['version']              || payload[:version],
          drift:                normalize_drift(payload['drift'] || payload[:drift]),
          received_at:          Time.current
        }
        Rails.cache.write(PEER_STATE_CACHE_KEY, normalized, expires_in: PEER_STATE_TTL)
      end

      # Outbound shape: capped path lists per category, plus full
      # counts so the receiving side can show "showing 500 of 6772."
      def build_drift_payload(diff)
        {
          counts: {
            modified: diff[:modified].size,
            added:    diff[:added].size,
            deleted:  diff[:deleted].size
          },
          modified:  diff[:modified].first(DRIFT_LIST_CAP),
          added:     diff[:added].first(DRIFT_LIST_CAP),
          deleted:   diff[:deleted].first(DRIFT_LIST_CAP),
          truncated: diff[:modified].size > DRIFT_LIST_CAP ||
                     diff[:added].size > DRIFT_LIST_CAP ||
                     diff[:deleted].size > DRIFT_LIST_CAP
        }
      end

      # Inbound shape: tolerant of missing fields (peer might be
      # running older code without drift info) and of either string
      # or symbol keys.
      def normalize_drift(drift)
        return nil unless drift
        counts = drift['counts'] || drift[:counts] || {}
        {
          counts: {
            modified: counts['modified'] || counts[:modified] || (drift['modified'] || drift[:modified] || []).size,
            added:    counts['added']    || counts[:added]    || (drift['added']    || drift[:added]    || []).size,
            deleted:  counts['deleted']  || counts[:deleted]  || (drift['deleted']  || drift[:deleted]  || []).size
          },
          modified:  drift['modified']  || drift[:modified]  || [],
          added:     drift['added']     || drift[:added]     || [],
          deleted:   drift['deleted']   || drift[:deleted]   || [],
          truncated: drift['truncated'] || drift[:truncated] || false
        }
      end
    end
  end
end
