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
  # ruby_confirmed/resume are set only when the user approved an in-browser
  # Ruby install after the update paused at the checking_ruby step (see
  # UpdateOrchestrator#ensure_ruby_available). A resume reuses the existing
  # staging/ clone and DB backup and picks up right where it paused.
  def perform(version:, status_id:, ruby_confirmed: false, resume: false)
    status = UpdateStatus.find(status_id)

    status.update!(
      current_step: resume ? "Resuming update…" : "Starting update…",
      started_at:   status.started_at || Time.current,
    )

    RoeUpdater::UpdateOrchestrator.start_update(
      version, status, ruby_confirmed: ruby_confirmed, resume: resume
    )
  rescue => e
    Rails.logger.error "Update job failed: #{e.message}"
    raise
  end
end
