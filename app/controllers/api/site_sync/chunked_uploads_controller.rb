require "digest"

module Api
  module SiteSync
    # Large files over HTTP Site Sync, in pieces.
    #
    # A normal push packs files into one tar per request. A big video
    # rendition (hundreds of MB) can't go that way: one request that size
    # dies on the way — the proxy in front of the live site, a request
    # timeout, or memory, since the tar is built in RAM. So any file over
    # the batch limit is sent here instead, a few MB at a time, and joined
    # back together on this side:
    #
    #   POST /api/site_sync/upload_chunk?upload_id=…&offset=…&size=…
    #        body: the next piece of the file (raw bytes)
    #   POST /api/site_sync/upload_finish
    #        { upload_id, path, size, sha256, mtime }
    #
    # Pieces land in /site/.sync-uploads/<upload_id>.part — on the same disk
    # as /site, so the finished file is moved into place with a rename (no
    # second copy of a 1 GB file), and excluded from the Ledger and backups.
    # The id is derived from the file's path, size, mtime and checksum, so a
    # sync that's interrupted and run again picks up where it stopped: a
    # piece sent at the wrong offset gets 409 with how much has arrived.
    #
    # Nothing reaches /site until the whole file is here and its SHA-256
    # matches, and only paths a normal upload could write (the same path
    # checks as TarArchive.unpack) are accepted.
    class ChunkedUploadsController < BaseController
      STAGING_DIR = ".sync-uploads".freeze
      UPLOAD_ID   = /\A\h{32}\z/
      # A piece is a few MB; anything much bigger is refused rather than read.
      MAX_CHUNK_BYTES = 64 * 1024 * 1024
      # Pieces from a sync that never finished are cleared after this long.
      STALE_AFTER = 2.days

      def chunk
        id = params[:upload_id].to_s
        return render(json: { error: "bad upload_id" }, status: :bad_request) unless id.match?(UPLOAD_ID)

        offset = Integer(params[:offset].to_s, exception: false)
        size   = Integer(params[:size].to_s, exception: false)
        return render(json: { error: "bad offset or size" }, status: :bad_request) unless offset && size && offset >= 0 && size.positive?

        length = request.content_length.to_i
        return render(json: { error: "piece too large" }, status: :payload_too_large) if length > MAX_CHUNK_BYTES

        part = part_path(id)
        FileUtils.mkdir_p(File.dirname(part))
        sweep_stale! if offset.zero?

        received = File.exist?(part) ? File.size(part) : 0
        if offset != received
          # Out of step (a retry, or a sync picking up again): say how much is
          # here so the sender carries on from there.
          return render json: { received: received }, status: :conflict
        end

        File.open(part, "ab") { |f| IO.copy_stream(request.body, f) }
        received = File.size(part)

        if received > size
          FileUtils.rm_f(part)
          return render json: { error: "more bytes than the file's size" }, status: :unprocessable_entity
        end

        render json: { received: received }
      end

      def finish
        body = JSON.parse(request.body.read)
        id = body["upload_id"].to_s
        return render(json: { error: "bad upload_id" }, status: :bad_request) unless id.match?(UPLOAD_ID)

        site = File.expand_path(::RoeSitePaths::SITE_PATH)
        rel  = ::SiteSync::TarArchive.safe_relative_path(body["path"].to_s, site)
        if rel.blank? || ::SiteSync::Ledger.excluded?(rel)
          return render json: { error: "path not accepted" }, status: :unprocessable_entity
        end

        part = part_path(id)
        return render(json: { error: "nothing uploaded for this id" }, status: :not_found) unless File.file?(part)

        unless File.size(part) == body["size"].to_i
          return render json: { error: "incomplete", received: File.size(part) }, status: :conflict
        end

        unless Digest::SHA256.file(part).hexdigest == body["sha256"].to_s
          FileUtils.rm_f(part) # corrupt: start again rather than resume onto it
          return render json: { error: "checksum mismatch" }, status: :unprocessable_entity
        end

        target = File.join(site, rel)
        FileUtils.mkdir_p(File.dirname(target))
        File.rename(part, target)
        if (mtime = body["mtime"].to_i).positive?
          t = Time.at(mtime)
          File.utime(t, t, target)
        end

        render json: { ok: true, path: rel, size: File.size(target) }
      rescue JSON::ParserError
        render json: { error: "invalid json" }, status: :bad_request
      rescue ::SiteSync::TarArchive::UnsafeEntry => e
        render json: { error: "unsafe path: #{e.message}" }, status: :unprocessable_entity
      end

      private

      def part_path(id) = File.join(::RoeSitePaths::SITE_PATH, STAGING_DIR, "#{id}.part")

      def sweep_stale!
        Dir.glob(File.join(::RoeSitePaths::SITE_PATH, STAGING_DIR, "*.part")).each do |f|
          File.delete(f) if File.mtime(f) < STALE_AFTER.ago
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
