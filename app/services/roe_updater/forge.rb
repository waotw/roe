# frozen_string_literal: true

module RoeUpdater
  # Where Roe looks for its own releases.
  #
  # The host used to be written into seven places across VersionChecker and
  # Downloader. Moving forge meant editing all of them and hoping none was
  # missed — and the update path is the one thing that must not break, because
  # a user whose updater points at a dead host has no way back in.
  #
  # That's also why this is a list rather than a host. Whatever is compiled in
  # is what an install has when the network fails it: an install that knows one
  # place to look is stranded the day that place goes away, and it can't be
  # rescued by an update because updating is the broken thing.
  #
  # A single indirection doesn't fix that, it relocates it. Pointing everyone at
  # go-roe.com trades "a forge is a single point of failure" for "a domain is",
  # which is a worse bet — and it's circular: when go-roe.com is down, the
  # client would need go-roe.com to tell it where else to go.
  #
  # So: go-roe.com first, because it can be repointed without shipping a
  # release, then the forges directly. Entries after the first must never be
  # more redirects — a redirect can't be its own fallback.
  #
  # Version discovery is `git ls-remote --tags` and download is `git clone`,
  # both of which work against any git host over HTTPS. Only #api_release_url
  # is forge-specific, and release notes degrade gracefully when it misses.
  class Forge
    DEFAULT_HOST = "codeberg.org"
    DEFAULT_REPO = "waotw/roe"

    # Ordered. First that answers wins.
    DEFAULT_MIRRORS = [
      "https://go-roe.com/roe.git",
      "https://codeberg.org/waotw/roe"
    ].freeze

    class << self
      def host = ENV["ROE_FORGE_HOST"].presence || DEFAULT_HOST
      def repo = ENV["ROE_FORGE_REPO"].presence || DEFAULT_REPO

      # Every place to try, in order.
      #
      # ROE_FORGE_URLS (comma-separated) replaces the list outright. The older
      # ROE_FORGE_HOST/REPO pair also replaces it rather than joining it —
      # someone who pinned a host meant that host, and silently falling through
      # to ours would ignore them.
      def mirrors
        explicit = ENV["ROE_FORGE_URLS"].to_s.split(",").map(&:strip).reject(&:empty?)
        return explicit if explicit.any?

        return [ "https://#{host}/#{repo}" ] if ENV["ROE_FORGE_HOST"].present? || ENV["ROE_FORGE_REPO"].present?

        DEFAULT_MIRRORS
      end

      # The preferred mirror. Kept for callers that want one URL and for
      # anything that reads a single forge out of habit.
      def https_url = mirrors.first

      # Fallback for a private repo, using the user's agent. SSH has no
      # redirect equivalent, so this stays a direct host.
      def ssh_url = "git@#{host}:#{repo}.git"

      # Mirrors we can build forge URLs for. go-roe.com redirects the git path
      # only, so a release page or API call aimed at it would 404 rather than
      # fail over — it's a fine place to clone from and a bad one to link to.
      def forge_mirrors = mirrors.reject { |url| URI.parse(url).host == "go-roe.com" rescue true }

      # The human-facing page for a release, shown in the update panel.
      def release_page_url(tag, base = forge_mirrors.first || https_url)
        "#{base.delete_suffix('.git')}/releases/tag/#{tag}"
      end

      # Release metadata, whose shape differs per forge. GitHub answers on a
      # separate API host; Forgejo and Gitea answer on the forge itself.
      # Returns nil for a host we have no shape for — go-roe.com is a redirect,
      # not an API, so asking it would 404 rather than fail over.
      def api_release_url(tag, base = https_url)
        uri  = URI.parse(base)
        path = uri.path.to_s.delete_prefix("/").delete_suffix(".git")
        return nil if path.empty?

        case uri.host
        when "github.com" then "https://api.github.com/repos/#{path}/releases/tags/#{tag}"
        when "go-roe.com" then nil
        else                   "https://#{uri.host}/api/v1/repos/#{path}/releases/tags/#{tag}"
        end
      rescue URI::InvalidURIError
        nil
      end

      # Every release-metadata URL worth trying, in mirror order, skipping
      # mirrors with no known API shape.
      def api_release_urls(tag) = mirrors.filter_map { |base| api_release_url(tag, base) }
    end
  end
end
