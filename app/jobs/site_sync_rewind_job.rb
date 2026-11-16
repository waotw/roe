# Rewinds the newest sync (SiteSync::Rewind) in the background: it talks to
# live, and putting large files back can take a while. Writes the same status
# key as SiteSyncTransferJob, so the Site Sync page shows its progress and no
# sync can start while it runs.
class SiteSyncRewindJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    @started_at = Time.current
    event = SiteSync::Versions.event(event_id)
    raise SiteSync::Rewind::Error, "That sync is no longer in the history." unless event

    @event_at = event[:at]
    step(:starting)
    SiteSync::Rewind.perform!(event, on_step: method(:step), on_progress: progress_proc)
    write(state: :completed, completed_at: Time.current)
  rescue SiteSync::Rewind::Error, SiteSync::Versions::SaveFailed => e
    # Stopped on purpose, before or while saving: nothing to retry blindly.
    Rails.logger.warn "[SiteSyncRewindJob] #{e.class}: #{e.message}"
    write(state: :failed, step: @step, completed_at: Time.current, error: e.message)
  rescue => e
    Rails.logger.error "[SiteSyncRewindJob] #{e.class}: #{e.message}"
    write(state: :failed, step: @step, completed_at: Time.current, error: e.message)
    raise
  end

  private

  def step(key)
    @step = key
    @progress = nil
    Rails.logger.info "[SiteSyncRewindJob] step: #{key}"
    write(state: :running, step: key)
  end

  def progress_proc
    ->(completed:, total:, bytes_done: nil, bytes_total: nil, current: nil) {
      @progress = { completed: completed, total: total }
      @progress.merge!(bytes_done: bytes_done, bytes_total: bytes_total) if bytes_total.to_i.positive?
      @progress[:current] = current if current
      write(state: :running, step: @step)
    }
  end

  def write(data)
    payload = { kind: :rewind, started_at: @started_at, event_at: @event_at }.merge(data)
    payload[:progress] = @progress if @progress && data[:state] == :running
    Rails.cache.write(SiteSyncTransferJob::STATUS_CACHE_KEY, payload, expires_in: SiteSyncTransferJob::STATUS_TTL)
  end
end
