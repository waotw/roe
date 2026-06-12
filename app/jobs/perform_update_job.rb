class PerformUpdateJob < ApplicationJob
  queue_as :default

  # The UpdateStatus record is created in the controller before the
  # redirect so the in-progress panel + JS polling can render
  # immediately (instead of waiting for the queue worker to pick the
  # job up). The job is just handed the record's id and stamps
  # started_at when it actually begins. status_id is required —
  # there's no fallback path that creates a fresh record here, so an
  # accidental invocation without it crashes loudly rather than
  # silently creating a duplicate.
  def perform(version:, status_id:)
    status = UpdateStatus.find(status_id)

    status.update!(
      current_step: "Starting update…",
      started_at:   Time.current,
    )

    RoeUpdater::UpdateOrchestrator.start_update(version, status)
  rescue => e
    Rails.logger.error "Update job failed: #{e.message}"
    raise
  end
end
