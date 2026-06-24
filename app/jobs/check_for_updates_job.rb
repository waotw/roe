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
  # Runs even on dev installs (branch HEAD). The in-app updater is
  # disabled for them, but the amber dot is still useful visibility —
  # tells a Roe maintainer that the public release has moved past their
  # current VERSION file. The Updates page enforces the action block,
  # not this background check.
  #
  # Flag maintenance lives inside VersionChecker.check_for_updates now:
  # writes true on confirmed-available, deletes on confirmed-up-to-date,
  # leaves the flag alone on network errors or partial responses (so a
  # transient blip doesn't flicker the dot off).
  def perform
    RoeUpdater::VersionChecker.check_for_updates
  end
end
