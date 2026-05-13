module Api
  module SiteSync
    # Shared base for all machine-to-machine /api/site_sync endpoints.
    # Lives outside the /admin namespace because it's our own Rails app
    # talking to itself across environments — no logged-in user, just
    # a bearer token from SyncConfig.
    #
    # Inherits from ActionController::API to skip CSRF, browser version
    # checks, and the rest of the HTML-client middleware.
    class BaseController < ActionController::API
      before_action :verify_token

      private

      # Constant-time comparison so an attacker can't time their way to
      # the right token. Empty/missing token always fails.
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
