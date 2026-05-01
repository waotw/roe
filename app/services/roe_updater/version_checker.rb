module RoeUpdater
  class VersionChecker
    SOURCEHUT_REPO = "~benjaminwelch/roe"
    GIT_REMOTE_URL = "https://git.sr.ht/~benjaminwelch/roe"
    CACHE_KEY = "roe_latest_version"
    CACHE_TTL = 1.hour

    class << self
      def current_version
        @current_version ||= load_current_version
      end

      def check_for_updates
        cached = Rails.cache.read(CACHE_KEY)
        return cached if cached

        latest = fetch_latest_version
        return nil if latest.nil?

        result = {
          current_version: current_version,
          latest_version: latest[:version],
          update_available: update_available?(current_version, latest[:version]),
          release_url: latest[:url],
          release_notes: latest[:notes],
          published_at: latest[:published_at]
        }

        Rails.cache.write(CACHE_KEY, result, expires_in: CACHE_TTL)
        result
      rescue => e
        Rails.logger.error "Update check failed: #{e.message}"
        nil
      end

      def clear_cache
        Rails.cache.delete(CACHE_KEY)
      end

      private

      def load_current_version
        version_file = File.join(RoeSitePaths::ROE_ROOT, 'VERSION')
        return "0.0.0" unless File.exist?(version_file)
        
        config = YAML.load_file(version_file)
        config['version'] || "0.0.0"
      rescue => e
        Rails.logger.error "Failed to load version file: #{e.message}"
        "0.0.0"
      end

      def fetch_latest_version
        return mock_release if Rails.env.development? || Rails.env.test?
        fetch_via_git_tags || fetch_via_sourcehut_api
      rescue => e
        Rails.logger.error "Failed to fetch latest version: #{e.message}"
        nil
      end

      def fetch_via_git_tags
        return nil unless git_available?

        tags_output = `git ls-remote --tags #{GIT_REMOTE_URL} 2>/dev/null`
        return nil if tags_output.empty?

        tags = tags_output.lines.map do |line|
          match = line.match(/refs\/tags\/(v?(.+))/)
          match[2] if match
        end.compact

        version_tags = tags.select { |t| t.match(/^\d+\.\d+(\.\d+)?$/) }
        return nil if version_tags.empty?

        latest_tag = version_tags.sort { |a, b| compare_versions(a, b) }.last

        {
          version: latest_tag,
          url: "https://git.sr.ht/#{SOURCEHUT_REPO}/refs/#{latest_tag}",
          notes: "View the changelog and commit history on Sourcehut.",
          published_at: Time.now.iso8601
        }
      rescue => e
        Rails.logger.error "Git tags fetch failed: #{e.message}"
        nil
      end

      def fetch_via_sourcehut_api
        uri = URI("https://git.sr.ht/api/~benjaminwelch/repos/roe/log")
        response = Net::HTTP.get_response(uri)
        return nil unless response.is_a?(Net::HTTPSuccess)
        
        data = JSON.parse(response.body)
        commits = data['results'] || []
        return nil if commits.empty?

        latest_commit = commits.first
        
        {
          version: extract_version_from_commit(latest_commit),
          url: "https://git.sr.ht/#{SOURCEHUT_REPO}",
          notes: "Latest commit: #{latest_commit['message']&.lines&.first}",
          published_at: latest_commit['timestamp']
        }
      rescue => e
        Rails.logger.error "Sourcehut API fetch failed: #{e.message}"
        nil
      end

      def extract_version_from_commit(commit)
        message = commit['message'] || ""
        if match = message.match(/(?:release|version)\s*v?(\d+\.\d+(?:\.\d+)?)/i)
          match[1]
        else
          "unknown"
        end
      end

      def git_available?
        system('which git > /dev/null 2>&1')
      end

      def update_available?(current, latest)
        return false if latest.nil? || current.nil?
        return false if latest == "unknown"
        compare_versions(latest, current) > 0
      end

      def compare_versions(a, b)
        a_parts = a.to_s.split('.').map(&:to_i)
        b_parts = b.to_s.split('.').map(&:to_i)
        
        max_length = [a_parts.length, b_parts.length].max
        a_parts.fill(0, a_parts.length...max_length)
        b_parts.fill(0, b_parts.length...max_length)
        
        a_parts.zip(b_parts).each do |a_part, b_part|
          return 1 if a_part > b_part
          return -1 if a_part < b_part
        end
        
        0
      end

      def mock_release
        {
          version: "0.2.0",
          url: "https://git.sr.ht/#{SOURCEHUT_REPO}/refs/v0.2.0",
          notes: "## What's New\n\n- Feature A\n- Feature B\n- Bug fixes\n\nView full changelog on Sourcehut.",
          published_at: Time.now.iso8601
        }
      end
    end
  end
end
