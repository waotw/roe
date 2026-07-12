require "net/http"
require "json"
require "stringio"

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
    PEER_STATE_CACHE_KEY     = "site_sync:peer_state".freeze
    PEER_STATE_TTL           = 1.day            # stop trusting peer state after this
    LAST_EXCHANGE_CACHE_KEY  = "site_sync:last_exchange".freeze
    LAST_EXCHANGE_TTL        = 1.day
    REFRESH_STALE_AFTER      = 60.seconds       # threshold for opportunistic refresh
    PEER_REACHABLE_WINDOW    = 2.hours          # peer counts as "reachable" if we
    # heard from them within this window
    HTTP_TIMEOUT_SECONDS     = 5

    # Read timeout for bulk file transfers (download/upload of a gzip'd
    # tar). Much larger than the 5s/30s used for state pings — a batch
    # transfer of changed media can take a while, and we'd rather wait
    # than fail a legitimate sync.
    TRANSFER_TIMEOUT_SECONDS = 300

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
        recorded_files = recorded&.dig("files") || {}

        state = {
          fingerprint:          SiteSync::Ledger.fingerprint_of(current_files),
          # Recompute recorded_fingerprint from the recorded manifest
          # rather than reading the stored value. Ledgers written
          # before fingerprint_of was made canonical (sorted) have
          # stale fingerprints baked in; recomputing here means old
          # ledgers self-heal on first exchange without anyone needing
          # to click "Mark Synced." Always-fresh, always-canonical.
          recorded_fingerprint: recorded ? SiteSync::Ledger.fingerprint_of(recorded_files) : nil,
          env:                  Rails.env.to_s,
          version:              Time.now.utc.iso8601,
          # Non-secret hints about this side so the peer can render accurate
          # restart/recovery instructions (e.g. "cd <folder> && kamal app boot"
          # on the local machine). Stored plaintext on the peer.
          env_info: {
            folder_name:   File.basename(RoeSitePaths::ROE_ROOT),
            deploy_target: SiteSync.deploy_target&.to_s
          }
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
        # If their fingerprint matches ours, both sides actually
        # have the same content — even if our ledger says otherwise.
        # Refresh our ledger to reflect reality. This is what makes
        # the system self-correct after a `notifying_peer` failure
        # or any other case where bookkeeping drifted from truth.
        self_heal_ledger_if_in_sync_with(payload)
        local_state
      end

      # Outbound: send our state to the peer, store theirs. Returns
      # the peer's state on success, nil on failure (network error,
      # auth failure, malformed response, etc.). Failures are logged
      # but never raised — exchange is best-effort.
      def call_peer
        return nil unless can_call_peer?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/exchange"))

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.read_timeout = HTTP_TIMEOUT_SECONDS
        http.open_timeout = HTTP_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{token}"
        request.body             = local_state.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn "[SiteSync::Exchange] peer responded #{response.code}: #{response.body}"
          # Track the specific error type
          error_type = case response.code.to_i
          when 401 then :auth_error
          when 404 then :not_found
          when 500..599 then :server_error
          else :request_error
          end
          # Pull the peer's error message out of the JSON body when one
          # was sent (controllers in this app render
          # { "error": "ClassName: message" } on rescue). Trim because
          # raw bodies can be HTML pages from Rails' default error
          # handler — first line is enough for the UI hint.
          error_message = begin
            JSON.parse(response.body).then { |h| h["error"] || h["message"] }
          rescue
            response.body.to_s.lines.first&.strip&.first(500)
          end
          save_exchange_result(
            success:       false,
            error_type:    error_type,
            http_code:     response.code,
            error_message: error_message
          )
          return nil
        end

        parsed = JSON.parse(response.body)
        save_peer_state(parsed)
        save_exchange_result(success: true)
        # Symmetric self-heal on dev's side: if peer's fingerprint
        # matches ours, our ledger should reflect that we're in
        # sync (in case our local ledger update failed earlier).
        self_heal_ledger_if_in_sync_with(parsed)
        parsed
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] peer call failed: #{e.class} #{e.message}"
        save_exchange_result(success: false, error_type: :network_error, error_message: e.message)
        nil
      end

      # Track the result of the last exchange attempt for UI feedback
      def save_exchange_result(success:, error_type: nil, http_code: nil, error_message: nil)
        Rails.cache.write(
          LAST_EXCHANGE_CACHE_KEY,
          {
            success: success,
            error_type: error_type,
            http_code: http_code,
            error_message: error_message,
            attempted_at: Time.current
          },
          expires_in: LAST_EXCHANGE_TTL
        )
      end

      # Get the last exchange attempt result
      def last_exchange_result
        Rails.cache.read(LAST_EXCHANGE_CACHE_KEY)
      end

      # Clear the last exchange result (e.g., after config changes)
      def clear_exchange_result
        Rails.cache.delete(LAST_EXCHANGE_CACHE_KEY)
      end

      # Tell the peer to run ContentSync.sync_all so its Post/Page/
      # Product/Medium tables reconcile against the new on-disk state
      # after a push. Without this, the peer's admin keeps showing rows
      # for files that just got deleted on disk (orphans) and doesn't
      # show rows for files that just landed — ContentSync only runs
      # at boot via config/initializers/content_management.rb.
      #
      # Push-only. Pull side calls ContentSync.sync_all locally and
      # in-process (no API hop needed for our own DB).
      #
      # Best-effort: returns true on success, false on any failure.
      # Failures are logged but don't bubble out so a partial-success
      # sync still completes cleanly from the user's perspective.
      def reconcile_peer_content!
        unless can_call_peer?
          Rails.logger.warn "[SiteSync::Exchange] reconcile_peer_content skipped — can_call_peer? is false"
          return false
        end

        uri = URI.parse(File.join(peer_url, "/api/site_sync/reconcile_content"))
        Rails.logger.info "[SiteSync::Exchange] reconcile_peer_content → POST #{uri}"

        # ContentSync.sync_all walks the whole site, so the peer may
        # need a few seconds (especially with many media files). Use
        # a longer read timeout for this specific call than the default
        # 30s in post_to_peer — but cap it so a wedged peer doesn't
        # block the calling job forever.
        with_retries(label: "reconcile_peer_content", max_retries: 2) do
          response = post_to_peer(uri, "{}", read_timeout: 120)
          if response.nil?
            raise "no response (network error)"
          elsif response.is_a?(Net::HTTPSuccess)
            Rails.logger.info "[SiteSync::Exchange] reconcile_peer_content OK"
            return true
          elsif response.code.to_i.between?(500, 599)
            raise "HTTP #{response.code}: #{response.body}"
          else
            Rails.logger.warn "[SiteSync::Exchange] reconcile_peer_content FAILED: HTTP #{response.code} from #{uri} — body: #{response.body}"
            return false
          end
        end
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] reconcile_peer_content ERROR after retries: #{e.class} #{e.message}"
        false
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
        unless can_call_peer?
          Rails.logger.warn "[SiteSync::Exchange] refresh_peer_ledger skipped — can_call_peer? is false (peer_url present? #{peer_url.present?}, token present? #{token.present?}, env: #{Rails.env})"
          return false
        end

        uri = URI.parse(File.join(peer_url, "/api/site_sync/refresh_ledger"))
        Rails.logger.info "[SiteSync::Exchange] refresh_peer_ledger → POST #{uri}"

        # 1 attempt + 2 retries on transient failures (network blip,
        # 502/503 from the peer, etc.). Auth/4xx failures aren't
        # retried — they won't fix themselves. Retries use brief
        # exponential backoff (1s, then 2s) so we don't compound a
        # struggling peer.
        with_retries(label: "refresh_peer_ledger", max_retries: 2) do
          response = post_to_peer(uri, "{}")
          if response.nil?
            raise "no response (network error)"
          elsif response.is_a?(Net::HTTPSuccess)
            Rails.logger.info "[SiteSync::Exchange] refresh_peer_ledger OK — peer reports fingerprint #{(JSON.parse(response.body) rescue {})['fingerprint']}"
            return true
          elsif response.code.to_i.between?(500, 599)
            # Server error — transient enough to retry
            raise "HTTP #{response.code}: #{response.body}"
          else
            # 4xx (auth, bad request, etc.) — don't retry, return failure
            Rails.logger.warn "[SiteSync::Exchange] refresh_peer_ledger FAILED: HTTP #{response.code} from #{uri} — body: #{response.body}"
            return false
          end
        end
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] refresh_peer_ledger ERROR after retries: #{e.class} #{e.message}"
        false
      end

      # Ask the peer for per-file state (size + mtime) of a specific
      # set of paths. Returns a hash of `{ "path" => {size, mtime} or nil }`.
      # Used by post-failure reassessment to figure out which specific
      # files made it through a partial sync.
      #
      # Returns {} on any failure (network, auth, etc.) — caller falls
      # back to coarser fingerprint comparison.
      def fetch_peer_file_states(paths)
        return {} unless can_call_peer?
        paths = Array(paths).reject(&:blank?).uniq
        return {} if paths.empty?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/file_states"))
        response = post_to_peer(uri, { paths: paths }.to_json)
        return {} unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)["files"] || {}
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] fetch_peer_file_states failed: #{e.class} #{e.message}"
        {}
      end

      # Ask the peer for the SHA256 of a specific set of paths. Returns a
      # hash of `{ "path" => "<sha256>" }` (missing files omitted). Used by
      # the reconciler to confirm real conflicts — an edit/edit pair whose
      # content actually matches (mtime skew) isn't one. Returns {} on any
      # failure, so the caller treats candidates as real conflicts (safe).
      def fetch_peer_file_hashes(paths)
        return {} unless can_call_peer?
        paths = Array(paths).reject(&:blank?).uniq
        return {} if paths.empty?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/file_hashes"))
        response = post_to_peer(uri, { paths: paths }.to_json)
        return {} unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)["hashes"] || {}
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] fetch_peer_file_hashes failed: #{e.class} #{e.message}"
        {}
      end

      # Fetch the complete file manifest from the peer. Returns a hash
      # of `{ "path" => {size, mtime}, ... }` suitable for diffing against
      # the local manifest. Used for accurate cross-site comparison.
      #
      # Returns nil on failure (network, auth, etc.) — caller should
      # fall back to recorded ledger comparison.
      def fetch_peer_manifest
        return nil unless can_call_peer?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/manifest"))
        response = get_from_peer(uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        data = JSON.parse(response.body)
        {
          "files" => data["files"] || {},
          "fingerprint" => data["fingerprint"],
          "file_count" => data["file_count"]
        }
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] fetch_peer_manifest failed: #{e.class} #{e.message}"
        nil
      end

      # Download a set of /site files from the peer as a gzip'd tar.
      # POSTs the requested relative paths; the peer packs them (dropping
      # anything excluded/unsafe) and streams the tar back. Returns the
      # raw tar bytes, or nil on any failure. Used by HttpTransport's pull
      # and hardlink backup. Callers must not pass an empty list — an
      # empty set means "nothing to fetch," which the transport handles
      # before calling here.
      def download_files(paths)
        return nil unless can_call_peer?
        paths = Array(paths).reject(&:blank?).uniq
        return nil if paths.empty?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/download"))
        response = post_to_peer(uri, { paths: paths }.to_json, read_timeout: TRANSFER_TIMEOUT_SECONDS)
        return nil unless response.is_a?(Net::HTTPSuccess)

        response.body
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] download_files failed: #{e.class} #{e.message}"
        nil
      end

      # Pull a fresh encrypted DB blob from the peer (the live site). The
      # peer stages a current encrypted copy and streams the ciphertext.
      # Returns the blob bytes, or nil when there's nothing to pull — the
      # peer has no backup passphrase set (HTTP 204) or is unreachable.
      # One-directional by design: we only ever pull the DB, never push it.
      def pull_peer_database
        return nil unless can_call_peer?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/database"))
        response = post_to_peer(uri, "{}", read_timeout: TRANSFER_TIMEOUT_SECONDS)
        return nil if response.nil?

        if response.is_a?(Net::HTTPNoContent)
          Rails.logger.info "[SiteSync::Exchange] peer has no backup passphrase set; skipping DB backup"
          return nil
        end
        return nil unless response.is_a?(Net::HTTPSuccess)

        response.body
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] pull_peer_database failed: #{e.class} #{e.message}"
        nil
      end

      # Upload a batch of changed /site files to the peer as a multipart
      # POST: the gzip'd tar (`archive`), a JSON per-file manifest
      # (`manifest`, so the peer can restore mtimes), and a JSON list of
      # paths to delete (`deleted`). The peer unpacks into its /site,
      # restores mtimes, and applies the deletions. Returns the parsed
      # response hash on success, nil on any failure. Used by
      # HttpTransport's push.
      def upload_files(archive_bytes:, manifest:, deleted:)
        return nil unless can_call_peer?

        uri  = URI.parse(File.join(peer_url, "/api/site_sync/upload"))
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.read_timeout = TRANSFER_TIMEOUT_SECONDS
        http.open_timeout = HTTP_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Authorization"] = "Bearer #{token}"
        request.set_form(
          [
            [ "manifest", manifest.to_json ],
            [ "deleted",  Array(deleted).to_json ],
            [ "archive",  StringIO.new(archive_bytes.to_s),
              { filename: "site-sync.tar.gz", content_type: "application/gzip" } ]
          ],
          "multipart/form-data"
        )

        response = http.request(request)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue JSON::ParserError
        # 2xx but unparseable body — the transfer landed; treat as success.
        { "ok" => true }
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] upload_files failed: #{e.class} #{e.message}"
        nil
      end

      # Send a batch of imported members to the peer for publish. The
      # peer skips any member whose email already exists. Returns the
      # parsed response hash on success ({inserted, skipped, errors})
      # or nil on any failure (auth, network, peer error). Caller
      # should treat nil as "this batch didn't make it" and surface
      # the error rather than silently moving on.
      def publish_members(batch)
        return nil unless can_call_peer?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/publish_members"))
        response = post_to_peer(uri, { members: batch }.to_json)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] publish_members failed: #{e.class} #{e.message}"
        nil
      end

      # Same shape as publish_members, but for newsletter_sends. The peer
      # resolves post_id via metadata (substack_post_id → url_name) and
      # member_id via email; per-record outcomes are returned in the
      # response so the job can show "247 inserted, 12 had no matching
      # post on live (probably need to re-run site sync)."
      def publish_newsletter_sends(batch)
        return nil unless can_call_peer?

        uri = URI.parse(File.join(peer_url, "/api/site_sync/publish_newsletter_sends"))
        response = post_to_peer(uri, { sends: batch }.to_json)
        return nil unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] publish_newsletter_sends failed: #{e.class} #{e.message}"
        nil
      end

      # Tiny HTTP helper — separated out so the retry loop above can
      # treat network errors and HTTP responses uniformly. Per-call
      # read_timeout lets endpoints that do real server-side work
      # (e.g. reconcile_content walking the whole /site) raise the
      # ceiling without globally bumping it for cheap pings.
      def post_to_peer(uri, body, read_timeout: 30)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.read_timeout = read_timeout
        http.open_timeout = HTTP_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"]  = "application/json"
        request["Authorization"] = "Bearer #{token}"
        request.body             = body

        http.request(request)
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] HTTP error to #{uri}: #{e.class} #{e.message}"
        nil
      end

      # HTTP GET helper for fetching data from peer (used by manifest fetch).
      def get_from_peer(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.read_timeout = 30
        http.open_timeout = HTTP_TIMEOUT_SECONDS

        request = Net::HTTP::Get.new(uri.request_uri)
        request["Authorization"] = "Bearer #{token}"

        http.request(request)
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] HTTP GET error to #{uri}: #{e.class} #{e.message}"
        nil
      end

      # Generic retry-with-backoff. Yields once + up to `max_retries`
      # additional times on failure. Backoff sleeps 1s, 2s, 4s, ...
      # (linear-ish growth). Used for network-y operations that
      # commonly hit transient errors; logs each attempt so we can
      # trace what happened.
      def with_retries(label:, max_retries: 2)
        attempts = 0
        begin
          attempts += 1
          yield
        rescue => e
          if attempts <= max_retries
            backoff = attempts # 1, 2, ...
            Rails.logger.warn "[SiteSync::Exchange] #{label}: attempt #{attempts} failed (#{e.message}); retrying in #{backoff}s"
            sleep backoff
            retry
          else
            raise
          end
        end
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
        when "production"  then "Live site"
        when "development" then "Local site"
        else                    peer_state&.dig(:env)&.to_s&.capitalize
        end
      end

      # When did we last hear from the peer? Used for the debug
      # panel; nil if no contact yet.
      def last_contact_at
        peer_state&.dig(:received_at)
      end

      # True if the cross-env exchange can be considered the source
      # of truth right now — i.e., we've heard from the peer recently
      # enough that its drift signal is meaningful. The admin UI uses
      # this to hide the local-drift fallback when the cross-env
      # panel is doing its job, and to show it when offline.
      def peer_reachable?
        contact = last_contact_at
        contact.present? && contact > PEER_REACHABLE_WINDOW.ago
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

        # Use explicitly set peer_url, or fall back to Site URL from settings
        SyncConfig.current.peer_url.presence || ::SiteConfig.site_url
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

      # If the peer reports the same fingerprint we have right now,
      # both sides have identical content — full stop. Make sure our
      # ledger reflects that. This is the safety net for cases where
      # a sync's content transfer succeeded but the bookkeeping
      # afterwards (notifying_peer, write_current!, etc.) failed.
      # The exchange itself heals the ledger, so the user doesn't
      # see lingering "drift" on a side that's actually in sync.
      #
      # Skips when fingerprints differ (real drift exists — don't
      # paper over it) or when our ledger already records this state.
      def self_heal_ledger_if_in_sync_with(payload)
        peer_fp = payload["fingerprint"] || payload[:fingerprint]
        return if peer_fp.blank?

        current_fp = SiteSync::Ledger.fingerprint_for(RoeSitePaths::SITE_PATH)
        return unless current_fp == peer_fp

        recorded = SiteSync::Ledger.recorded
        return if recorded && recorded["fingerprint"] == current_fp

        Rails.logger.info "[SiteSync::Exchange] self-heal: peer fingerprint matches ours, refreshing local ledger"
        SiteSync::Ledger.write_current!
        SiteSync::Checker.clear_cache
        Rails.cache.delete("site_sync:current_fingerprint")
      rescue => e
        Rails.logger.warn "[SiteSync::Exchange] self-heal failed: #{e.class} #{e.message}"
      end

      # Symbolize keys defensively — JSON.parse returns string keys,
      # but `local_state` builds a symbol-keyed hash, so callers
      # can rely on either path producing the same shape.
      def save_peer_state(payload)
        normalized = {
          fingerprint:          payload["fingerprint"]          || payload[:fingerprint],
          recorded_fingerprint: payload["recorded_fingerprint"] || payload[:recorded_fingerprint],
          env:                  payload["env"]                  || payload[:env],
          version:              payload["version"]              || payload[:version],
          drift:                normalize_drift(payload["drift"] || payload[:drift]),
          received_at:          Time.current
        }
        Rails.cache.write(PEER_STATE_CACHE_KEY, normalized, expires_in: PEER_STATE_TTL)

        # Persist the peer's environment hints (plaintext), so recovery
        # instructions survive restarts and an encryption-broken boot.
        env_info = payload["env_info"] || payload[:env_info]
        SyncConfig.current.merge_peer_env!(env_info) if env_info.present?
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
        counts = drift["counts"] || drift[:counts] || {}
        {
          counts: {
            modified: counts["modified"] || counts[:modified] || (drift["modified"] || drift[:modified] || []).size,
            added:    counts["added"]    || counts[:added]    || (drift["added"]    || drift[:added]    || []).size,
            deleted:  counts["deleted"]  || counts[:deleted]  || (drift["deleted"]  || drift[:deleted]  || []).size
          },
          modified:  drift["modified"]  || drift[:modified]  || [],
          added:     drift["added"]     || drift[:added]     || [],
          deleted:   drift["deleted"]   || drift[:deleted]   || [],
          truncated: drift["truncated"] || drift[:truncated] || false
        }
      end
    end
  end
end
