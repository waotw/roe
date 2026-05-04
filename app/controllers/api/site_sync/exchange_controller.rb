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
