module RoeUpdater
  class VersionChecker
    CODEBERG_REPO = "waotw/roe"
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
        version_file = File.join(RoeSitePaths::ROE_ROOT, "VERSION")
        return "0.0.0" unless File.exist?(version_file)

        config = YAML.load_file(version_file)
        config["version"] || "0.0.0"
      rescue => e
        Rails.logger.error "Failed to load version file: #{e.message}"
        "0.0.0"
      end

      def fetch_latest_version
        # Mock the latest-release lookup when:
        #   - running tests (so we never hit the network), or
        #   - the developer explicitly opts in via ROE_MOCK_UPDATE=1
        return mock_release if Rails.env.test?
        return mock_release if ENV["ROE_MOCK_UPDATE"].present?

        Rails.logger.info "[VersionChecker] Checking for updates from Codeberg"

        # Try git tags with HTTPS -> SSH fallback
        git_result = fetch_via_git_tags
        if git_result
          Rails.logger.info "[VersionChecker] Found version: #{git_result[:version]}"
          return git_result
        end

        Rails.logger.error "[VersionChecker] Failed to fetch version from Codeberg"
        nil
      rescue => e
        Rails.logger.error "[VersionChecker] Failed to fetch latest version: #{e.class} - #{e.message}"
        nil
      end

      def fetch_via_git_tags
        return nil unless git_available?

        require "timeout"
        require "open3"

        # Build environment with SSH agent support for private repos
        env = {
          "GIT_TERMINAL_PROMPT" => "0",
          "SSH_AUTH_SOCK" => ENV["SSH_AUTH_SOCK"],
          "HOME" => ENV["HOME"]
        }.compact

        # Try HTTPS first (works for public repos without auth)
        https_url = "https://codeberg.org/#{CODEBERG_REPO}"

        begin
          stdout, stderr, status = nil, nil, nil
          Timeout.timeout(10) do
            stdout, stderr, status = Open3.capture3(env, "git", "ls-remote", "--tags", https_url)
          end

          if status.success? && stdout.present?
            return parse_git_tags_output(stdout)
          end
        rescue Timeout::Error
          Rails.logger.debug "[VersionChecker] HTTPS fetch timed out"
        end

        # HTTPS failed (private repo or timeout), try SSH
        ssh_url = "git@codeberg.org:#{CODEBERG_REPO}.git"

        begin
          output, status = nil, nil
          Timeout.timeout(15) do
            output, status = Open3.capture2e(env, "git", "ls-remote", "--tags", ssh_url)
          end

          if status.success? && output.present?
            tag_lines = output.lines.select { |line| line.match?(/^[a-f0-9]+\s+refs\/tags\//) }
            return parse_git_tags_output(tag_lines.join) if tag_lines.any?
          end
        rescue Timeout::Error
          Rails.logger.debug "[VersionChecker] SSH fetch timed out"
        end

        nil
      rescue => e
        Rails.logger.error "[VersionChecker] Git tags fetch failed: #{e.class} - #{e.message}"
        nil
      end

      def parse_git_tags_output(tags_output)
        tags = tags_output.lines.map do |line|
          match = line.match(/refs\/tags\/(v?(.+))/)
          match[2] if match
        end.compact

        version_tags = tags.select { |t| t.match(/^\d+\.\d+(\.\d+)?$/) }
        return nil if version_tags.empty?

        latest_tag = version_tags.sort { |a, b| compare_versions(a, b) }.last

        {
          version: latest_tag,
          url: "https://codeberg.org/#{CODEBERG_REPO}/releases/tag/#{latest_tag}",
          notes: "View the changelog and commit history on Codeberg.",
          published_at: Time.now.iso8601
        }
      end

      def git_available?
        system("which git > /dev/null 2>&1")
      end

      def update_available?(current, latest)
        return false if latest.nil? || current.nil?
        return false if latest == "unknown"
        compare_versions(latest, current) > 0
      end

      def compare_versions(a, b)
        a_parts = a.to_s.split(".").map(&:to_i)
        b_parts = b.to_s.split(".").map(&:to_i)

        max_length = [ a_parts.length, b_parts.length ].max
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
          url: "https://codeberg.org/#{CODEBERG_REPO}/releases/tag/v0.2.0",
          notes: "## What's New\n\n- Feature A\n- Feature B\n- Bug fixes\n\nView full changelog on Codeberg.",
          published_at: Time.now.iso8601
        }
      end
    end
  end
end
