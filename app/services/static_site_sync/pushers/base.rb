require "pathname"

# Shared scaffolding for protocol-specific pushers. Each subclass owns
# its own connection lifecycle and file-transfer primitives but shares
# the orchestration shape — walk the diff, upload-then-delete, report
# progress per item.
#
# Errors normalise into Pusher::ConnectionError / Pusher::TransferError
# so the push job and controller never need to know about Net::SFTP vs
# Net::FTP exception classes.
module StaticSiteSync
  module Pushers
    class Base
      def initialize(config:, root: RoeSitePaths::STATIC_SITE_PATH, progress_proc: nil)
        @config        = config
        @root          = Pathname.new(root)
        @progress_proc = progress_proc
      end

      # Subclass responsibilities:
      #   test_connection — open, verify the remote path, close.
      #   push!(diff)     — apply the diff, return { uploaded:, deleted: }.
      def test_connection; raise NotImplementedError; end
      def push!(_diff);   raise NotImplementedError; end

      protected

      def report(completed, total)
        @progress_proc&.call(completed: completed, total: total)
      end

      # Walk the diff once, calling the supplied per-item blocks. Keeps
      # the upload/delete loop identical across protocols — subclasses
      # only supply the actual transfer primitive.
      def walk(diff, upload:, delete:)
        uploaded = []
        deleted  = []
        total = diff.count
        done  = 0

        diff.upload_paths.each do |rel|
          upload.call(rel)
          uploaded << rel
          done += 1
          report(done, total)
        end

        diff.deleted.each do |rel|
          delete.call(rel)
          deleted << rel
          done += 1
          report(done, total)
        end

        { uploaded: uploaded, deleted: deleted }
      end
    end
  end
end
