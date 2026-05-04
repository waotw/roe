module Api
  module SiteSync
    # Inbound endpoint for cross-environment state exchange. Lives
    # outside the /admin namespace because it's machine-to-machine
    # — dev's Rails process talking to prod's, not a logged-in
    # human. Auth is a bearer token (Rails.application.credentials
    # :roe_sync :token) shared between both environments.
    #
    # Inherits from ActionController::API to skip CSRF, browser
    # version checks, and the rest of the middleware that's only
    # relevant for HTML clients. The peer is always our own Rails
    # app on the other side; it doesn't need cookies.
    class ExchangeController < ActionController::API
      before_action :verify_token

      # POST /api/site_sync/exchange
      # Body:    { fingerprint, recorded_fingerprint, env, version }
      # Returns: { fingerprint, recorded_fingerprint, env, version }
      def create
        payload = JSON.parse(request.body.read)
        render json: ::SiteSync::Exchange.handle_inbound(payload)
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      end

      # POST /api/site_sync/refresh_ledger
      #
      # Called by the peer right after it pushes content to us, so
      # our ledger reflects the new /site state instead of the pre-
      # push one. Without this, our drift detection would scream
      # "everything changed!" right after a successful push (because
      # rsync updated mtimes on every transferred file but our
      # ledger still has the old mtimes).
      #
      # No body needed — we just walk our own /site and write the
      # ledger to whatever's on disk now. Returns the resulting
      # fingerprint so the caller can sanity-check.
      def refresh_ledger
        Rails.logger.info "[Api::SiteSync::ExchangeController] refresh_ledger called from peer"
        ::SiteSync::Ledger.write_current!
        ::SiteSync::Checker.clear_cache
        Rails.cache.delete("site_sync:current_fingerprint")
        fp = ::SiteSync::Ledger.fingerprint_for(::RoeSitePaths::SITE_PATH)
        Rails.logger.info "[Api::SiteSync::ExchangeController] refresh_ledger wrote ledger; current fingerprint=#{fp}"
        render json: { ok: true, fingerprint: fp }
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] refresh_ledger FAILED: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { ok: false, error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      private

      # Constant-time comparison so an attacker can't time their
      # way to the right token. Empty/missing token always fails.
      def verify_token
        provided = request.headers['Authorization'].to_s.sub(/\ABearer\s+/, '')
        expected = SyncConfig.current.token.to_s

        if expected.blank?
          render json: { error: 'exchange not configured: SyncConfig token missing' }, status: :service_unavailable
          return
        end

        unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)
          render json: { error: 'unauthorized' }, status: :unauthorized
        end
      end
    end
  end
end
