class CheckForUpdatesJob < ApplicationJob
  queue_as :default

  # Runs hourly via config/recurring.yml (development only).
  # Checks Codeberg for the latest Roe release and writes a persistent
  # flag to Rails cache so the nav dot can read it without a network call.
  #
  # The flag has no TTL — it stays true until an update completes and
  # UpdateOrchestrator#complete_update clears it. This means the dot
  # stays visible across server restarts until the user actually updates.
  #
  # Skips the check entirely when running on a dev git checkout (branch
  # HEAD rather than detached tag) — the in-app updater is disabled there.
  def perform
    return if RoeUpdater::VersionChecker.dev_install?

    result = RoeUpdater::VersionChecker.check_for_updates
    return unless result

    if result[:update_available]
      Rails.cache.write(RoeUpdater::VersionChecker::UPDATE_AVAILABLE_KEY, true)
    end
    # Don't clear the flag on "no update" — only clear it when an update
    # completes (UpdateOrchestrator#complete_update). This prevents the
    # dot from flickering off if the check races with a version bump.
  end
end
