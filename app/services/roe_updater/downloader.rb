module RoeUpdater
  class Downloader
    class DownloadError < StandardError; end

    STAGING_PATH = File.join(RoeSitePaths::ROE_ROOT, "staging")

    class << self
      def download_version(version, status_record)
        cleanup_staging

        # Single source of truth for the repo location lives on
        # VersionChecker so the download host stays in sync with the
        # update-check host. If we ever move providers again, one
        # constant changes and both paths follow.
        git_url = "https://codeberg.org/#{RoeUpdater::VersionChecker::CODEBERG_REPO}"

        status_record.update!(
          current_step: "Downloading Roe #{version}...",
          log: (status_record.log || "") + "→ Downloading version #{version}...\n"
        )

        clone_cmd = "git clone --depth 1 --branch v#{version} #{git_url} '#{STAGING_PATH}' 2>&1"
        output = `#{clone_cmd}`

        unless $?.success?
          raise DownloadError, "Git clone failed: #{output}"
        end

        verify_download

        status_record.update!(
          log: (status_record.log || "") + "✓ Downloaded version #{version}\n"
        )

        STAGING_PATH
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
