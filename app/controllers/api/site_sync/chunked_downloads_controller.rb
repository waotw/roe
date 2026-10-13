require "digest"

module Api
  module SiteSync
    # Large files over HTTP Site Sync, in pieces, live → this machine. The
    # mirror of ChunkedUploadsController.
    #
    # The normal download packs files into one tar, built in memory, per
    # request. A 1.2 GB video can't go that way: the live server runs out of
    # memory, or the request outlives the proxy in front of it. That failure
    # stopped syncs that only wanted to back the video up. So any file over
    # the batch limit is fetched here instead, a few MB at a time:
    #
    #   POST /api/site_sync/download_info   { path }
    #        → { path, size, mtime, sha256 }
    #   POST /api/site_sync/download_chunk  { path, offset, length }
    #        → that many raw bytes of the file, from offset
    #
    # The caller checks the finished file against the SHA-256 before trusting
    # it, and resumes from what it already has after a failure. Only paths a
    # normal download could serve are accepted: inside /site, not excluded
    # from sync (system/secrets/, the ledger, …), a real file, not a symlink.
    class ChunkedDownloadsController < BaseController
      # A piece is a few MB; a request for much more is refused.
      MAX_CHUNK_BYTES = 64 * 1024 * 1024

      def info
        full, rel = resolve!
        return unless full

        stat = File.stat(full)
        render json: {
          path: rel,
          size: stat.size,
          mtime: stat.mtime.to_i,
          sha256: Digest::SHA256.file(full).hexdigest
        }
      end

      def chunk
        full, = resolve!
        return unless full

        offset = Integer(@payload["offset"].to_s, exception: false)
        length = Integer(@payload["length"].to_s, exception: false)
        unless offset && length && offset >= 0 && length.positive? && length <= MAX_CHUNK_BYTES
          return render json: { error: "bad offset or length" }, status: :bad_request
        end

        size = File.size(full)
        return render(json: { error: "offset past the end", size: size }, status: :range_not_satisfiable) if offset > size

        bytes = File.open(full, "rb") { |f| f.seek(offset); f.read(length) } || "".b
        response.headers["X-File-Size"] = size.to_s
        send_data bytes, type: "application/octet-stream", disposition: "attachment"
      end

      private

      # The requested file, or nil after rendering why not.
      def resolve!
        @payload = JSON.parse(request.body.read)
        site = File.expand_path(::RoeSitePaths::SITE_PATH)
        rel  = ::SiteSync::TarArchive.safe_relative_path(@payload["path"].to_s, site)

        if rel.blank? || rel == site || ::SiteSync::Ledger.excluded?(rel)
          render json: { error: "path not accepted" }, status: :unprocessable_entity
          return nil
        end

        full = File.join(site, rel)
        unless File.file?(full) && !File.symlink?(full)
          render json: { error: "no such file" }, status: :not_found
          return nil
        end

        [ full, rel ]
      rescue JSON::ParserError
        render json: { error: "invalid json" }, status: :bad_request
        nil
      rescue ::SiteSync::TarArchive::UnsafeEntry => e
        render json: { error: "unsafe path: #{e.message}" }, status: :unprocessable_entity
        nil
      end
    end
  end
end
