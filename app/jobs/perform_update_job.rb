class PerformUpdateJob < ApplicationJob
  queue_as :default

  def perform(version:)
    status = UpdateStatus.create!(
      status: "in_progress",
      from_version: RoeUpdater::VersionChecker.current_version,
      to_version: version,
      current_step: "Starting update...",
      started_at: Time.current
    )

    RoeUpdater::UpdateOrchestrator.start_update(version, status)
  rescue => e
    Rails.logger.error "Update job failed: #{e.message}"
    raise
  end
end
