module Api
  module SiteSync
    # Inbound endpoint for cross-environment state exchange. Auth
    # (bearer token via Authorization header) is handled by
    # Api::SiteSync::BaseController.
    class ExchangeController < BaseController
      # Upper bound on the number of paths a single download request may
      # name — a sanity cap so a malformed/hostile body can't ask us to
      # stat+pack an unbounded list.
      MAX_DOWNLOAD_PATHS = 50_000

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

      # POST /api/site_sync/file_hashes
      #
      # Body:    { paths: [ "posts/foo.md", ... ] }
      # Returns: { hashes: { "posts/foo.md": "<sha256>", ... } }
      #
      # Content hashes for the reconciler to confirm real conflicts — an
      # edit/edit pair whose bytes actually match (mtime skew) isn't a
      # conflict. Excluded/traversal paths are filtered, same as download.
      def file_hashes
        payload = JSON.parse(request.body.read)
        paths = Array(payload["paths"]).first(MAX_DOWNLOAD_PATHS).select do |p|
          p.is_a?(String) && !p.include?("..") && !p.start_with?("/") &&
            !::SiteSync::Ledger.excluded?(p)
        end

        render json: { hashes: ::SiteSync::Reconciler.hashes_for(paths) }
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] file_hashes FAILED: #{e.class} #{e.message}"
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

      # POST /api/site_sync/download
      #
      # Body:    { paths: [ "posts/foo.md", "media/img.jpg", ... ] }
      # Returns: application/gzip — a tar of the requested files.
      #
      # Requested paths are filtered before packing: anything with `..`,
      # an absolute path, or a Ledger-excluded prefix (system/secrets/,
      # db/, …) is dropped. So this endpoint can never be used to
      # exfiltrate a production key or read outside /site — it only ever
      # serves syncable content. Used by the peer's HttpTransport pull
      # and hardlink backup.
      def download
        payload = JSON.parse(request.body.read)
        paths = Array(payload["paths"]).first(MAX_DOWNLOAD_PATHS).select do |p|
          p.is_a?(String) && !p.include?("..") && !p.start_with?("/") &&
            !::SiteSync::Ledger.excluded?(p)
        end

        tar = ::SiteSync::TarArchive.pack(root: ::RoeSitePaths::SITE_PATH, paths: paths)
        send_data tar, type: "application/gzip", disposition: "attachment",
                       filename: "site-sync.tar.gz"
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] download FAILED: #{e.class} #{e.message}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      # POST /api/site_sync/upload   (multipart/form-data)
      #
      # Parts:
      #   archive  — gzip'd tar of changed files (SiteSync::TarArchive)
      #   manifest — JSON { "path" => {size, mtime} } for mtime restore
      #   deleted  — JSON [ "path", ... ] to remove from /site
      #
      # Unpacks the archive into /site (TarArchive refuses excluded or
      # traversal entries — a hostile archive can't write system/secrets/
      # or escape the root), restores each file's mtime from the manifest,
      # then applies the deletions (SiteWriter, equally guarded). The
      # peer's HttpTransport push calls refresh_ledger + reconcile_content
      # afterwards, so we don't do that bookkeeping here.
      # POST /api/site_sync/database
      #
      # Build a fresh encrypted DR bundle of THIS host's primary DB (database
      # + master.key + credentials) and stream the ciphertext. This is the ONE
      # endpoint that emits database bytes, and it can only ever emit
      # ciphertext — the plaintext DB never crosses this channel. 200 + blob
      # when a backup passphrase is set; 204 (no body) when none is, so the
      # caller skips cleanly. Built in a tempdir and returned as bytes, so it
      # never depends on a writable path outside /site on the container.
      def database
        blob = ::SiteSync::BackupManager.build_encrypted_db_bundle
        return head(:no_content) if blob.nil?

        send_data blob,
                  type:        "application/octet-stream",
                  disposition: "attachment",
                  filename:    "database.enc"
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] database FAILED: #{e.class} #{e.message}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      def upload
        archive = params[:archive]
        unless archive.respond_to?(:read)
          return render json: { error: "missing archive part" }, status: :bad_request
        end

        manifest = parse_json_param(params[:manifest], default: {})
        deleted  = parse_json_param(params[:deleted],  default: [])

        written = ::SiteSync::TarArchive.unpack(archive.read, dest: ::RoeSitePaths::SITE_PATH)
        ::SiteSync::SiteWriter.restore_mtimes(root: ::RoeSitePaths::SITE_PATH, manifest: manifest)
        removed = ::SiteSync::SiteWriter.delete_paths(root: ::RoeSitePaths::SITE_PATH, paths: deleted)

        render json: { ok: true, written: written.size, deleted: removed.size }
      rescue ::SiteSync::TarArchive::UnsafeEntry => e
        Rails.logger.warn "[Api::SiteSync::ExchangeController] upload rejected unsafe archive: #{e.message}"
        render json: { ok: false, error: "unsafe archive: #{e.message}" }, status: :unprocessable_entity
      rescue => e
        Rails.logger.error "[Api::SiteSync::ExchangeController] upload FAILED: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { ok: false, error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      private

      # Multipart non-file parts arrive as strings. Parse leniently:
      # blank → default, malformed → default (never 500 the whole upload
      # over a bad metadata blob; the archive itself is the source of
      # truth for what to write).
      def parse_json_param(value, default:)
        return default if value.blank?
        JSON.parse(value)
      rescue JSON::ParserError
        default
      end
    end
  end
end
