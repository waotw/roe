require "open3"

module RoeUpdater
  class Downloader
    class DownloadError < StandardError; end

    STAGING_PATH = File.join(RoeSitePaths::ROE_ROOT, "staging")

    class << self
      def download_version(version, status_record)
        cleanup_staging

        status_record.update!(
          current_step: "Downloading Roe #{version}...",
          log: (status_record.log || "") + "→ Downloading version #{version}...\n"
        )

        # Same list as the update check, walked the same way. Falling through
        # here matters on its own: a mirror can answer `ls-remote` and still
        # fail the clone — stale, half-synced, or dropping the connection on a
        # bigger transfer — and stopping at the first failure would strand an
        # update that another mirror could finish.
        last_output = nil

        RoeUpdater::Forge.mirrors.each do |git_url|
          cleanup_staging # a failed clone can leave a partial directory behind

          # Array form, no shell. The staging path contains whatever the install
          # directory is called — this repo lives under "/Volumes/S&M 2019/",
          # where an unquoted word would split into other commands — and the
          # version and URL are interpolated values. Passing argv directly
          # removes the quoting question rather than answering it, which is
          # also why Brakeman stops flagging this line.
          last_output, status = Open3.capture2e(
            "git", "clone", "--depth", "1", "--branch", "v#{version}", git_url, STAGING_PATH
          )
          next unless status.success?

          begin
            verify_download
          rescue DownloadError => e
            last_output = "#{e.message} (from #{git_url})"
            next
          end

          status_record.update!(
            log: (status_record.log || "") + "✓ Downloaded version #{version}\n"
          )
          return STAGING_PATH
        end

        raise DownloadError, "Git clone failed from every mirror. Last error: #{last_output}"

      rescue => e
        cleanup_staging
        raise DownloadError, "Download failed: #{e.message}"
      end

      def cleanup_staging
        FileUtils.rm_rf(STAGING_PATH) if File.exist?(STAGING_PATH)
      end

      private

      def verify_download
        required_files = [ "Gemfile", "config.ru", "app" ]

        required_files.each do |file|
          path = File.join(STAGING_PATH, file)
          unless File.exist?(path)
            raise DownloadError, "Download verification failed: missing #{file}"
          end
        end
      end
    end
  end
end
