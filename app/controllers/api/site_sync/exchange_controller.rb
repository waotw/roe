module Api
  module SiteSync
    # Inbound endpoint for cross-environment state exchange. Auth
    # (bearer token via Authorization header) is handled by
    # Api::SiteSync::BaseController.
    class ExchangeController < BaseController
      # POST /api/site_sync/exchange
      # Body:    { fingerprint, recorded_fingerprint, env, version }
      # Returns: { fingerprint, recorded_fingerprint, env, version }
      def create
        payload = JSON.parse(request.body.read)
        render json: ::SiteSync::Exchange.handle_inbound(payload)
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      rescue => e
        # Mirrors the rescue pattern in refresh_ledger / file_states /
        # manifest below. Without this, any failure in handle_inbound
        # (Ledger walk error, cache write blip, etc.) returns Rails'
        # default opaque 500 — the dev-side caller sees `HTTP 500` with
        # no message and no way to debug short of `fly ssh` into logs.
        Rails.logger.error "[Api::SiteSync::ExchangeController] exchange FAILED: #{e.class} #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
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

      # POST /api/site_sync/file_states
      #
      # Body:    { paths: [ "posts/foo.md", "media/img.jpg", ... ] }
      # Returns: { files: { "posts/foo.md": {size, mtime}, "media/img.jpg": null, ... } }
      #
      # nil for a path means "file doesn't exist on this side." Caller
      # uses this to compare per-file state across sides — typically
      # for post-failure reassessment to figure out which specific
      # files made it through and which didn't.
      def file_states
        payload = JSON.parse(request.body.read)
        paths = Array(payload["paths"]).first(2000) # cap to keep payload sane

        result = paths.each_with_object({}) do |path, h|
          # Defensive: refuse paths that try to escape /site
          if path.to_s.include?("..") || path.to_s.start_with?("/")
            h[path] = nil
            next
          end

          full = File.join(::RoeSitePaths::SITE_PATH, path)
          h[path] = if File.exist?(full)
            stat = File.stat(full)
            { "size" => stat.size, "mtime" => stat.mtime.to_i }
          end
        end

        render json: { files: result }
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] file_states FAILED: #{e.class} #{e.message}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      # POST /api/site_sync/reconcile_content
      #
      # Called by the peer right after it pushes content to us, so our
      # Post/Page/Product/Medium tables reconcile against the new on-
      # disk state. Without this, the FS gets the new files but rows
      # for now-gone files linger (orphan records) and rows for new
      # files don't exist (admin doesn't see them) until the next app
      # restart kicks ContentSync.sync_all via the boot initializer.
      #
      # ContentSync handles both directions — orphan removal via
      # handle_orphaned_* and new-record creation via the per-type
      # sync_* loops. Safe to call repeatedly.
      def reconcile_content
        Rails.logger.info "[Api::SiteSync::ExchangeController] reconcile_content called from peer"
        ContentSync.sync_all
        render json: { ok: true }
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] reconcile_content FAILED: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { ok: false, error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      # GET /api/site_sync/manifest
      #
      # Returns the full file manifest for the site directory.
      # Used for accurate cross-site comparison during sync operations.
      # Returns: { files: { "path/to/file": {size, mtime}, ... }, fingerprint: "..." }
      def manifest
        current = ::SiteSync::Ledger.current
        fingerprint = ::SiteSync::Ledger.fingerprint_of(current)

        render json: {
          files: current,
          fingerprint: fingerprint,
          file_count: current.count
        }
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] manifest FAILED: #{e.class} #{e.message}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end
    end
  end
end
