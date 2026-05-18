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
        # Mock the latest-release lookup when:
        #   - running tests (so we never hit the network), or
        #   - the developer explicitly opts in via ROE_MOCK_UPDATE=1
        # The previous "always mock in dev" behavior meant every dev
        # session showed a misleading "Update to 0.2.0 available" banner;
        # opting in keeps the dev experience honest while still letting
        # you exercise the update UI when you want to.
        return mock_release if Rails.env.test?
        return mock_release if ENV['ROE_MOCK_UPDATE'].present?

        Rails.logger.info "[VersionChecker] Starting update check from #{GIT_REMOTE_URL}"
        
        # Try git tags first
        Rails.logger.info "[VersionChecker] Attempting git tags fetch..."
        git_result = fetch_via_git_tags
        if git_result
          Rails.logger.info "[VersionChecker] Git tags fetch succeeded: #{git_result[:version]}"
          return git_result
        end
        
        # Fall back to Sourcehut API
        Rails.logger.info "[VersionChecker] Git tags fetch returned nil, trying Sourcehut API..."
        api_result = fetch_via_sourcehut_api
        if api_result
          Rails.logger.info "[VersionChecker] Sourcehut API fetch succeeded: #{api_result[:version]}"
          return api_result
        end
        
        Rails.logger.error "[VersionChecker] All fetch methods failed"
        nil
      rescue => e
        Rails.logger.error "[VersionChecker] Failed to fetch latest version: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        nil
      end

      def fetch_via_git_tags
        unless git_available?
          Rails.logger.info "[VersionChecker] Git not available on this system"
          return nil
        end

        Rails.logger.info "[VersionChecker] Running: git ls-remote --tags #{GIT_REMOTE_URL}"
        tags_output = `git ls-remote --tags #{GIT_REMOTE_URL} 2>/dev/null`
        Rails.logger.info "[VersionChecker] Git output length: #{tags_output.length} chars"
        
        if tags_output.empty?
          Rails.logger.info "[VersionChecker] Git output was empty"
          return nil
        end

        tags = tags_output.lines.map do |line|
          match = line.match(/refs\/tags\/(v?(.+))/)
          match[2] if match
        end.compact

        Rails.logger.info "[VersionChecker] Found #{tags.length} tags, #{tags.select { |t| t.match(/^\d+\.\d+(\.\d+)?$/) }.length} version tags"
        
        version_tags = tags.select { |t| t.match(/^\d+\.\d+(\.\d+)?$/) }
        if version_tags.empty?
          Rails.logger.info "[VersionChecker] No valid version tags found"
          return nil
        end

        latest_tag = version_tags.sort { |a, b| compare_versions(a, b) }.last
        Rails.logger.info "[VersionChecker] Latest tag: #{latest_tag}"

        {
          version: latest_tag,
          url: "https://git.sr.ht/#{SOURCEHUT_REPO}/refs/#{latest_tag}",
          notes: "View the changelog and commit history on Sourcehut.",
          published_at: Time.now.iso8601
        }
      rescue => e
        Rails.logger.error "[VersionChecker] Git tags fetch failed: #{e.class} - #{e.message}"
        nil
      end

      def fetch_via_sourcehut_api
        # Try the GraphQL API endpoint first (more reliable)
        uri = URI("https://git.sr.ht/query")
        Rails.logger.info "[VersionChecker] Making GraphQL API request to: #{uri}"
        
        # GraphQL query for repository refs/tags
        query = {
          query: <<~GRAPHQL
            query {
              repository(owner: "~benjaminwelch", name: "roe") {
                refs(type: TAGS, count: 10) {
                  results {
                    name
                  }
                }
              }
            }
          GRAPHQL
        }
        
        req = Net::HTTP::Post.new(uri)
        req['Content-Type'] = 'application/json'
        req.body = query.to_json
        
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(req)
        end
        
        Rails.logger.info "[VersionChecker] GraphQL API response code: #{response.code}"
        
        if response.is_a?(Net::HTTPSuccess)
          data = JSON.parse(response.body)
          
          if data['errors']
            Rails.logger.info "[VersionChecker] GraphQL errors: #{data['errors']}"
            return nil
          end
          
          tags = data.dig('data', 'repository', 'refs', 'results') || []
          Rails.logger.info "[VersionChecker] Found #{tags.length} tags via GraphQL"
          
          version_tags = tags.map { |t| t['name'] }.select { |t| t.match(/^v?\d+\.\d+(\.\d+)?$/) }
          
          if version_tags.any?
            latest_tag = version_tags.sort { |a, b| compare_versions(a.gsub(/^v/, ''), b.gsub(/^v/, '')) }.last
            Rails.logger.info "[VersionChecker] Latest version from GraphQL: #{latest_tag}"
            
            return {
              version: latest_tag.gsub(/^v/, ''),
              url: "https://git.sr.ht/#{SOURCEHUT_REPO}/refs/#{latest_tag}",
              notes: "View the changelog and commit history on Sourcehut.",
              published_at: Time.now.iso8601
            }
          end
        end
        
        Rails.logger.info "[VersionChecker] GraphQL API failed or no tags found, trying REST endpoint..."
        
        # Fallback to REST API - try the refs endpoint instead
        uri = URI("https://git.sr.ht/api/~benjaminwelch/repos/roe/refs")
        Rails.logger.info "[VersionChecker] Making REST API request to: #{uri}"
        
        response = Net::HTTP.get_response(uri)
        Rails.logger.info "[VersionChecker] REST API response code: #{response.code}"
        
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.info "[VersionChecker] REST API request failed: #{response.code} #{response.message}"
          return nil
        end
        
        data = JSON.parse(response.body)
        Rails.logger.info "[VersionChecker] REST API response keys: #{data.keys.inspect}"
        
        # Try to extract version from tags in the refs response
        refs = data['results'] || []
        tags = refs.select { |r| r['name']&.match(/^v?\d+\.\d+(\.\d+)?$/) }
        
        if tags.any?
          latest_tag = tags.sort { |a, b| compare_versions(a['name'].gsub(/^v/, ''), b['name'].gsub(/^v/, '')) }.last
          Rails.logger.info "[VersionChecker] Latest version from REST API: #{latest_tag['name']}"
          
          return {
            version: latest_tag['name'].gsub(/^v/, ''),
            url: "https://git.sr.ht/#{SOURCEHUT_REPO}/refs/#{latest_tag['name']}",
            notes: "View the changelog and commit history on Sourcehut.",
            published_at: latest_tag['created'] || Time.now.iso8601
          }
        end
        
        Rails.logger.info "[VersionChecker] No version tags found in API responses"
        nil
      rescue => e
        Rails.logger.error "[VersionChecker] Sourcehut API fetch failed: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.first(3).join("\n")
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
