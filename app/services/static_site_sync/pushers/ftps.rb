require "net/ftp"
require "openssl"
require "set"

# FTPS = FTP with explicit TLS (AUTH TLS on the control channel, plus
# data-channel encryption). Same port as plain FTP — typically 21.
# Most cheap shared hosts that advertise "FTP" actually support FTPS
# this way; the user just has to enable it in their client. We always
# enable it because plain FTP over the public internet is a non-starter
# for credentials and file content.
module StaticSiteSync
  module Pushers
    class Ftps < Base
      def test_connection
        with_session do |ftp|
          ftp.chdir(@config.remote_path)
          true
        end
      rescue Net::FTPPermError => e
        raise Pusher::ConnectionError, "Remote path not accessible: #{@config.remote_path} (#{e.message})"
      end

      def push!(diff)
        with_session do |ftp|
          # Net::FTP holds connection state at the session level —
          # remembering the working directory across uploads matters
          # for ensure_remote_dir performance. Reset to remote_path
          # at the start so relative chdir works.
          ftp.chdir(@config.remote_path)
          walk(diff,
            upload: ->(rel) { upload_file(ftp, rel) },
            delete: ->(rel) { delete_remote(ftp, rel) })
        end
      end

      private

      def with_session
        # TLS has to be configured at construction — Net::FTP has no ssl=
        # setter. A nil host defers the actual connect to the call below,
        # so our own timeout and error handling still wraps it.
        ftp = Net::FTP.new(nil, ssl: ssl_context_options)
        ftp.passive  = true
        ftp.open_timeout = 30
        ftp.read_timeout = 60

        ftp.connect(@config.host, @config.port || 21)
        ftp.login(@config.username, @config.password)
        yield ftp
      rescue SocketError
        raise Pusher::ConnectionError, unresolved_host_message
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
        raise Pusher::ConnectionError, "Could not connect to #{@config.host}: #{e.message}"
      rescue Net::FTPPermError => e
        raise Pusher::ConnectionError, "Authentication failed: #{e.message}"
      rescue OpenSSL::SSL::SSLError => e
        raise tls_certificate_failure?(e) ?
          Pusher::CertificateError.new(tls_certificate_message) :
          Pusher::ConnectionError.new("TLS handshake failed: #{e.message}")
      rescue Net::FTPError => e
        raise Pusher::ConnectionError, "FTP error: #{e.message}"
      ensure
        ftp&.close rescue nil
      end

      # Hash form turns on Net::FTP's TLS path. Verify the peer certificate
      # by default. FTPS on shared / cPanel hosts often uses a self-signed
      # or hostname-mismatched cert; when the user turns verification off we
      # keep the channel encrypted but accept any certificate. VERIFY_NONE
      # also makes Net::FTP skip its post-connection hostname check.
      def ssl_context_options
        mode = @config.verify_tls ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
        { verify_mode: mode }
      end

      # A verification failure — untrusted / self-signed / expired cert, or a
      # hostname that doesn't match — is distinct from a genuine handshake
      # problem: the channel would still encrypt, we just can't confirm the
      # host's identity. Only possible while we're actually verifying, so a
      # host we've already chosen to trust (verify_tls off) never lands here.
      def tls_certificate_failure?(error)
        @config.verify_tls &&
          error.message.match?(/certificate verify failed|does not match|hostname/i)
      end

      def tls_certificate_message
        "#{@config.host} presented a TLS certificate Roe couldn't verify. " \
          "Shared and cPanel hosts often use self-signed or mismatched certificates."
      end

      def upload_file(ftp, rel)
        local_path  = @root.join(rel).to_s
        remote_path = File.join(@config.remote_path, rel)
        ensure_remote_dir(ftp, File.dirname(remote_path))
        ftp.putbinaryfile(local_path, remote_path)
      rescue Net::FTPError => e
        raise Pusher::TransferError, "Upload failed for #{rel}: #{e.message}"
      end

      def delete_remote(ftp, rel)
        ftp.delete(File.join(@config.remote_path, rel))
      rescue Net::FTPPermError
        # 550 = file not present. Same semantic as SFTP — absence is
        # the desired end state.
      rescue Net::FTPError => e
        raise Pusher::TransferError, "Delete failed for #{rel}: #{e.message}"
      end

      # mkdir -p over FTP — same shape as the SFTP version, just with
      # Net::FTP's primitives. `mkdir` raises if the directory already
      # exists, so we swallow that.
      def ensure_remote_dir(ftp, dir)
        return if dir == @config.remote_path || dir == "." || dir == "/"
        return if @ensured_dirs&.include?(dir)
        @ensured_dirs ||= Set.new

        ensure_remote_dir(ftp, File.dirname(dir))
        begin
          ftp.mkdir(dir)
        rescue Net::FTPPermError
          # Already exists — fine.
        rescue Net::FTPError => e
          raise Pusher::TransferError, "Could not create remote directory #{dir}: #{e.message}"
        end
        @ensured_dirs << dir
      end
    end
  end
end
