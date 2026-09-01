# frozen_string_literal: true

module RoeUpdater
  # Where Roe looks for its own releases.
  #
  # The host used to be written into seven places across VersionChecker and
  # Downloader. Moving forge meant editing all of them and hoping none was
  # missed — and the update path is the one thing that must not break, because
  # a user whose updater points at a dead host has no way back in.
  #
  # Defaults are Codeberg, so nothing changes until something sets otherwise.
  # Overridable by environment so a fork, a mirror, or a move is configuration
  # rather than a patch.
  #
  # Version discovery is `git ls-remote --tags`, which works against any git
  # host over HTTPS. Only #api_release_url is forge-specific — that's Forgejo's
  # (and Gitea's) shape, and GitHub's differs. Release notes are the only thing
  # that depends on it, and their absence degrades gracefully.
  class Forge
    DEFAULT_HOST = "codeberg.org"
    DEFAULT_REPO = "waotw/roe"

    class << self
      def host = ENV["ROE_FORGE_HOST"].presence || DEFAULT_HOST
      def repo = ENV["ROE_FORGE_REPO"].presence || DEFAULT_REPO

      # Clone/fetch over HTTPS — works unauthenticated for a public repo.
      def https_url = "https://#{host}/#{repo}"

      # Fallback for a private repo, using the user's agent.
      def ssh_url = "git@#{host}:#{repo}.git"

      # The human-facing page for a release, shown in the update panel.
      def release_page_url(tag) = "#{https_url}/releases/tag/#{tag}"

      # Forgejo/Gitea release metadata. The one forge-specific call.
      def api_release_url(tag) = "https://#{host}/api/v1/repos/#{repo}/releases/tags/#{tag}"
    end
  end
end
