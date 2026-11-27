module RoeUpdater
  # An in-process update (before the hand-off, or a release without
  # bin/update) runs inside Roe's job process. Restarting Roe partway stops
  # it, and its record stays "in progress" for good, which blocks every later
  # update. When the installed version is already the one it was installing,
  # it has been quiet for a while, and Roe has started since, Roe is running
  # the new code: mark it finished.
  class StuckUpdate
    QUIET_FOR = 20.minutes

    def self.finish_if_installed(status)
      return false unless status&.status == "in_progress"
      return false if Handoff.dir_for(status)
      return false unless status.updated_at < QUIET_FOR.ago
      return false unless VersionChecker.current_version.to_s == status.to_version.to_s

      # Roe has started since the update went quiet, so it's running the
      # new code rather than still waiting on the update.
      booted = Rails.application.config.try(:server_boot_time)
      return false unless booted && booted > status.updated_at

      status.update!(
        status: "completed",
        current_step: "Update completed successfully",
        progress_percent: 100,
        completed_at: status.updated_at,
        log: (status.log || "") + "[#{Time.current.strftime('%H:%M:%S')}] The update stopped partway, " \
                                  "but Roe #{status.to_version} was installed and has started since. Marked finished.\n"
      )
      true
    end
  end
end
