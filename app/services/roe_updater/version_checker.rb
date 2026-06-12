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
        # Capture both forms of each tag:
        #   original — what git knows, including the required `v` prefix
        #              (used for Codeberg API calls, release URLs, and
        #              for the Downloader's `git clone --branch vX.Y.Z`)
        #   stripped — the bare version (used for VERSION-file comparison
        #              and the value the rest of Roe stores/displays)
        #
        # The `v` prefix is REQUIRED. Roe's convention follows the wider
        # ecosystem: bare numbers in code (`VERSION`, displays, comparison)
        # and `v`-prefixed tags in git. A tag pushed without the prefix
        # (e.g. `0.0.9` instead of `v0.0.9`) is intentionally ignored here
        # — otherwise VersionChecker would happily surface it as an
        # available update and Downloader would then fail trying to
        # `--branch v0.0.9` on a tag that doesn't exist.
        #
        # The regex anchor `$` filters out git's dereferenced-tag lines
        # like `v0.1.0^{}` automatically.
        pairs = tags_output.lines.map do |line|
          match = line.match(/refs\/tags\/(v(\d+\.\d+(?:\.\d+)?))$/)
          [ match[1], match[2] ] if match
        end.compact

        return nil if pairs.empty?

        latest_original, latest_version =
          pairs.sort { |a, b| compare_versions(a[1], b[1]) }.last

        # Best-effort: enrich with real release metadata from the Codeberg
        # API. If the tag has no associated release object, the API is
        # down, or the network fails, we fall back to the bare tag link
        # and a generic note — the update flow still works.
        release = fetch_release_metadata(latest_original) || {}

        {
          version:      latest_version,
          url:          release[:html_url] || "https://codeberg.org/#{CODEBERG_REPO}/releases/tag/#{latest_original}",
          notes:        build_summary(release[:name], release[:body]),
          published_at: release[:published_at] || Time.now.iso8601
        }
      end

      # Fetch release metadata for a given tag from the Codeberg (Gitea)
      # API. Returns a hash with :name, :body, :html_url, :published_at —
      # or nil if the release doesn't exist (e.g., tag was pushed without
      # creating a release object) or the request failed for any reason.
      def fetch_release_metadata(tag)
        require "net/http"
        require "json"

        url = URI("https://codeberg.org/api/v1/repos/#{CODEBERG_REPO}/releases/tags/#{tag}")

        response = nil
        Timeout.timeout(5) do
          http = Net::HTTP.new(url.host, url.port)
          http.use_ssl = true
          http.open_timeout = 3
          http.read_timeout = 5

          request = Net::HTTP::Get.new(url)
          request["Accept"] = "application/json"
          request["User-Agent"] = "Roe-VersionChecker"

          response = http.request(request)
        end

        return nil unless response&.code == "200"

        data = JSON.parse(response.body)
        {
          name:         data["name"],
          body:         data["body"],
          html_url:     data["html_url"],
          published_at: data["published_at"] || data["created_at"]
        }
      rescue => e
        Rails.logger.debug "[VersionChecker] Release metadata fetch failed: #{e.class} - #{e.message}"
        nil
      end

      # Compose the release-notes preview the admin Updates page shows.
      # Sourced from the release title (if any) + as much of the body
      # as fits in a panel-friendly preview length. Falls back to a
      # generic message when nothing is available — covers the "git
      # tag without a Codeberg release" case.
      #
      # Truncates at ~600 chars on a word boundary so the panel doesn't
      # blow up to fill the page on long release notes — the view
      # already shows a "View full release notes on Codeberg →" link
      # below, so anyone who wants the full thing follows it.
      #
      # Light markdown cleanup: strips leading `#` from heading lines
      # so `## What's new in 0.0.11` reads as `What's new in 0.0.11`
      # in the panel. Other markers (bullets `-`, emphasis `**`, code
      # `` ` ``) are left in place — they're tolerable in a plain-text
      # preview and stripping them aggressively risks mangling content
      # that uses them legitimately (e.g. a flag name with hyphens).
      def build_summary(name, body)
        title = name.to_s.strip.presence
        body_text = clean_markdown_headings(body.to_s.strip)

        parts = []
        parts << title if title
        parts << body_text if body_text.present?

        return "View the changelog and commit history on Codeberg." if parts.empty?

        full = parts.join("\n\n")
        full.length > 600 ? full.truncate(600, separator: " ", omission: "…") : full
      end

      # Strip leading ATX heading markers (`#`, `##`, `###`, …) from
      # each line. Preserves indentation, list markers, and inline
      # emphasis — only the line-leading `#`s are removed.
      def clean_markdown_headings(text)
        text.lines.map { |line| line.sub(/\A#+\s*/, "") }.join
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
