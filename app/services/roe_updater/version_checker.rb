module RoeUpdater
  class VersionChecker
    # Kept as an alias so anything still referencing it resolves to the
    # configured forge rather than a second, drifting copy of the answer.
    CODEBERG_REPO = RoeUpdater::Forge::DEFAULT_REPO
    CACHE_KEY = "roe_latest_version"
    CACHE_TTL = 1.hour
    # Persistent flag — no TTL. Set by CheckForUpdatesJob when an update
    # is available. Cleared by UpdateOrchestrator#complete_update after
    # a successful update. Read by the nav helper to show the amber dot.
    UPDATE_AVAILABLE_KEY = "roe_update_available"

    class << self
      def current_version
        @current_version ||= load_current_version
      end

      def dev_install?
        @dev_install ||= check_dev_install
      end

      # True when this install should see prerelease tags. Two paths
      # in:
      #   1. dev_install? — you're on a git branch working on Roe.
      #      Implicit opt-in, no setting needed.
      #   2. site.yml's `update_channel: nightly` — explicit opt-in for
      #      a fresh user install. Lets a maintainer exercise the
      #      updater end-to-end against a tagged release without
      #      cloning the repo.
      # Default site.yml ships `update_channel: stable`, so user
      # installs that never touch the setting behave exactly as
      # before — only stable tags reach them.
      def prerelease_channel?
        return true if dev_install?
        SiteConfig.get("update_channel").to_s == "nightly"
      rescue StandardError
        dev_install?
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

        # Prerelease channel — only populated when the install is a dev
        # clone AND a `-suffix` tag exists. User installs never see
        # these fields (the inner classifier in parse_git_tags_output
        # returns nil for non-dev). Hidden also when the prerelease is
        # ≤ the latest stable (no point testing a tag that's already
        # superseded by the regular update path).
        if (pre = latest[:prerelease]) &&
           compare_versions(pre[:version], latest[:version]) > 0
          result.merge!(
            prerelease_version: pre[:version],
            prerelease_available: update_available?(current_version, pre[:version]),
            prerelease_url: pre[:url],
            prerelease_notes: pre[:notes],
            prerelease_published_at: pre[:published_at]
          )
        end

        Rails.cache.write(CACHE_KEY, result, expires_in: CACHE_TTL)

        # Maintain the persistent "update available" flag (the one the
        # nav-bar amber dot reads from). The background CheckForUpdatesJob
        # writes `true` when an update is available; here we *clear* the
        # flag when a confirmed-good check finds no update available, so
        # a user's manual recheck reflects reality.
        #
        # Safe to clear only when:
        #   - fetch_latest_version succeeded (not nil — guarded above)
        #   - the check definitively says no update is available
        # i.e. we're not clearing on a network glitch or partial response.
        if result[:update_available]
          Rails.cache.write(UPDATE_AVAILABLE_KEY, true)
        else
          Rails.cache.delete(UPDATE_AVAILABLE_KEY)
        end

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

        # Try every mirror over HTTPS, in order (works for public repos without
        # auth). An unreachable host fails in seconds, so walking the list costs
        # nothing on the happy path and is the whole point on the sad one.
        RoeUpdater::Forge.mirrors.each do |https_url|
          stdout, status = nil, nil
          Timeout.timeout(10) do
            stdout, _stderr, status = Open3.capture3(env, "git", "ls-remote", "--tags", https_url)
          end

          if status&.success? && stdout.present?
            return parse_git_tags_output(stdout)
          end

          Rails.logger.debug "[VersionChecker] No tags from #{https_url}, trying the next mirror"
        rescue Timeout::Error
          Rails.logger.debug "[VersionChecker] #{https_url} timed out, trying the next mirror"
        end

        # HTTPS failed (private repo or timeout), try SSH
        ssh_url = RoeUpdater::Forge.ssh_url

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
        # Pre-release suffixes (`-nightly`, `-rc.1`, `-dev.5`, etc.) are
        # accepted by the regex but treated separately — user installs
        # filter them out entirely; dev installs see them as an opt-in
        # secondary update path. SemVer 2.0 grammar for the suffix.
        #
        # The regex anchor `$` filters out git's dereferenced-tag lines
        # like `v0.1.0^{}` automatically.
        pairs = tags_output.lines.map do |line|
          match = line.match(/refs\/tags\/(v(\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9.-]+)?))$/)
          [ match[1], match[2] ] if match
        end.compact

        return nil if pairs.empty?

        stable_pairs    = pairs.reject { |_, ver| tag_is_prerelease?(ver) }
        prerelease_pairs = pairs.select { |_, ver| tag_is_prerelease?(ver) }

        latest_stable     = pick_latest(stable_pairs)
        latest_prerelease = pick_latest(prerelease_pairs)

        # Stable result is the canonical return shape — all existing
        # callers (CheckForUpdatesJob, the admin UI's primary update
        # path) keep working unchanged. Prerelease is surfaced as a
        # nested key only when the install is a dev clone AND a
        # prerelease exists; otherwise nil so nothing shows up for users.
        result = build_version_record(latest_stable)
        return nil if result.nil?

        if prerelease_channel? && latest_prerelease
          pre_record = build_version_record(latest_prerelease)
          result = result.merge(prerelease: pre_record) if pre_record
        end

        result
      end

      # Picks the highest-precedence tag from a list of [original, stripped]
      # pairs using Gem::Version, which understands SemVer's pre-release
      # ordering (0.0.36-nightly.1 < 0.0.36 < 0.0.36-rc.1 is wrong;
      # 0.0.36-nightly.1 < 0.0.36 is correct). The previous numeric-only
      # comparator silently put -nightly tags AHEAD of stables — Gem::Version
      # respects the suffix rules.
      def pick_latest(pairs)
        return nil if pairs.empty?
        pairs.max_by { |_, ver| Gem::Version.new(ver) }
      end

      def build_version_record(pair)
        return nil unless pair
        original, version = pair
        release = fetch_release_metadata(original) || {}
        {
          version:      version,
          url:          release[:html_url] || RoeUpdater::Forge.release_page_url(original),
          notes:        build_summary(release[:name], release[:body]),
          published_at: release[:published_at] || Time.now.iso8601
        }
      end

      # True when the version string carries a SemVer pre-release suffix
      # (anything after a `-`, e.g. `-nightly`, `-rc.1`, `-dev.5`). The
      # absence of a suffix marks a stable release that user installs
      # are allowed to see.
      def tag_is_prerelease?(version_str)
        version_str.to_s.include?("-")
      end

      # Fetch release metadata for a given tag from the Codeberg (Gitea)
      # API. Returns a hash with :name, :body, :html_url, :published_at —
      # or nil if the release doesn't exist (e.g., tag was pushed without
      # creating a release object) or the request failed for any reason.
      def fetch_release_metadata(tag)
        require "net/http"
        require "json"

        # Try each mirror that has a known API shape. Release notes are
        # best-effort — every path here already returns nil on failure — so a
        # mirror that doesn't answer just means trying the next one.
        RoeUpdater::Forge.api_release_urls(tag).each do |api_url|
          notes = fetch_release_metadata_from(URI(api_url))
          return notes if notes
        end

        nil
      end

      def fetch_release_metadata_from(url)
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

      # Returns true when current/ is a live git branch checkout (i.e. a
      # developer working on Roe itself), rather than a detached HEAD from
      # a tagged release clone (i.e. a normal user install).
      #
      # Detection strategy: ask git for the symbolic HEAD ref.
      #   - Detached HEAD (user install): `git symbolic-ref HEAD` exits
      #     non-zero — no branch name, just a commit SHA.
      #   - Named branch (dev checkout): exits 0 and prints
      #     refs/heads/main (or whatever branch).
      #
      # Falls back to false (not a dev install) on any error so that a
      # missing or broken git setup never accidentally locks out updates.
      def check_dev_install
        return false unless git_available?

        require "open3"
        _, status = Open3.capture2e(
          "git", "-C", Rails.root.to_s,
          "symbolic-ref", "--quiet", "HEAD"
        )
        status.success?
      rescue => e
        Rails.logger.debug "[VersionChecker] dev_install? check failed: #{e.message}"
        false
      end

      def update_available?(current, latest)
        return false if latest.nil? || current.nil?
        return false if latest == "unknown"
        compare_versions(latest, current) > 0
      end

      def compare_versions(a, b)
        # Gem::Version is SemVer 2.0 aware — knows that 0.0.36-nightly.1
        # sorts BEFORE 0.0.36, and 0.0.36 sorts before 0.0.37-rc.1. The
        # old numeric-only comparator silently treated -nightly tags as
        # later (the hyphen suffix got coerced to 0 by to_i), so they'd
        # appear "ahead of" stable releases.
        Gem::Version.new(a.to_s) <=> Gem::Version.new(b.to_s)
      rescue ArgumentError
        # Fall back to the old numeric comparator if either input isn't
        # a valid Gem::Version string — keeps the method total even
        # when called with garbage.
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
          url: RoeUpdater::Forge.release_page_url("v0.2.0"),
          notes: "## What's New\n\n- Feature A\n- Feature B\n- Bug fixes\n\nView full changelog on Codeberg.",
          published_at: Time.now.iso8601
        }
      end
    end
  end
end
