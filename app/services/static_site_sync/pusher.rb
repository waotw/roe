# Factory that returns the right protocol-specific pusher for a given
# config. Each implementation lives under `pushers/` and exposes the
# same two methods — `test_connection` and `push!(diff)` — so callers
# (the push job, the controller's connection-test action) don't need
# to know which protocol they're talking to.
#
# ZIP isn't a "push" in the network sense — it generates a downloadable
# archive — and the controller routes it to a separate synchronous
# action, so this factory only knows about the network protocols.
module StaticSiteSync
  module Pusher
    class ConnectionError < StandardError; end
    class TransferError   < StandardError; end

    def self.for(config:, root: RoeSitePaths::STATIC_SITE_PATH, progress_proc: nil)
      case config.protocol
      when "sftp"
        Pushers::Sftp.new(config: config, root: root, progress_proc: progress_proc)
      when "ftps"
        Pushers::Ftps.new(config: config, root: root, progress_proc: progress_proc)
      else
        raise ArgumentError, "Pusher.for cannot dispatch protocol #{config.protocol.inspect} (handled out-of-band)"
      end
    end
  end
end
