require "net/sftp"
require "set"

module StaticSiteSync
  module Pushers
    class Sftp < Base
      def test_connection
        with_session do |sftp|
          attrs = sftp.stat!(@config.remote_path)
          raise Pusher::ConnectionError, "Remote path is not a directory: #{@config.remote_path}" unless attrs.directory?
          true
        end
      end

      def push!(diff)
        with_session do |sftp|
          walk(diff,
            upload: ->(rel) { upload_file(sftp, rel) },
            delete: ->(rel) { delete_remote(sftp, rel) })
        end
      end

      private

      def with_session
        Net::SFTP.start(@config.host, @config.username, **ssh_options) do |sftp|
          yield sftp
        end
      rescue Net::SSH::AuthenticationFailed => e
        raise Pusher::ConnectionError, "Authentication failed: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::SSH::ConnectionTimeout => e
        raise Pusher::ConnectionError, "Could not connect to #{@config.host}: #{e.message}"
      rescue Net::SSH::HostKeyMismatch => e
        raise Pusher::ConnectionError, "Host key mismatch — host fingerprint changed. #{e.message}"
      rescue Net::SSH::Exception => e
        raise Pusher::ConnectionError, "SSH error: #{e.message}"
      end

      def ssh_options
        opts = { port: @config.port || 22, non_interactive: true, timeout: 30 }
        if @config.auth_mode_ssh_key?
          opts[:key_data]   = [ @config.ssh_private_key ]
          opts[:keys_only]  = true
        else
          opts[:password]     = @config.password
          opts[:auth_methods] = [ "password" ]
        end
        opts
      end

      def upload_file(sftp, rel)
        local_path  = @root.join(rel).to_s
        remote_path = File.join(@config.remote_path, rel)
        ensure_remote_dir(sftp, File.dirname(remote_path))
        sftp.upload!(local_path, remote_path)
      rescue Net::SFTP::StatusException => e
        raise Pusher::TransferError, "Upload failed for #{rel}: #{e.message}"
      end

      def delete_remote(sftp, rel)
        sftp.remove!(File.join(@config.remote_path, rel))
      rescue Net::SFTP::StatusException => e
        # Already-missing remote files aren't a failure — the goal was
        # absence and absence is what we have.
        raise Pusher::TransferError, "Delete failed for #{rel}: #{e.message}" unless e.code == Net::SFTP::Constants::StatusCodes::FX_NO_SUCH_FILE
      end

      # mkdir -p over SFTP: walk up parents, create any that don't exist.
      # SFTP has no native -p, so we test+create each segment.
      def ensure_remote_dir(sftp, dir)
        return if dir == @config.remote_path || dir == "." || dir == "/"
        return if @ensured_dirs&.include?(dir)
        @ensured_dirs ||= Set.new

        ensure_remote_dir(sftp, File.dirname(dir))
        begin
          sftp.stat!(dir)
        rescue Net::SFTP::StatusException => e
          raise unless e.code == Net::SFTP::Constants::StatusCodes::FX_NO_SUCH_FILE
          sftp.mkdir!(dir)
        end
        @ensured_dirs << dir
      end
    end
  end
end
