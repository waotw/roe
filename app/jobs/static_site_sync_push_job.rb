# Background job that pushes the SSG output in /static_site to the
# configured SFTP remote. Mirrors SiteSyncTransferJob's status-via-cache
# pattern so the admin page can poll a single key and reuse the same
# progress-panel UI for running / completed / failed states.
#
# One job at a time per install — uses a single status cache key so a
# new push always supersedes whatever's there. If a second push fires
# while one's running, the second one wins the cache slot; this is
# intentional (the user just clicked Push, they expect their click to
# be live).
class StaticSiteSyncPushJob < ApplicationJob
  queue_as :default

  STATUS_CACHE_KEY = "static_site_sync:transfer_status".freeze
  STATUS_TTL       = 1.day

  STEPS = {
    starting:           "Starting…",
    connecting:         "Connecting to remote…",
    computing_diff:     "Computing what changed…",
    uploading:          "Uploading changed files…",
    recording_manifest: "Recording push manifest…",
    finishing:          "Finishing up…"
  }.freeze

  def perform(full: false)
    @started_at = Time.current
    @config     = StaticSiteSyncConfig.current
    @manifest   = StaticSiteSync::PushManifest.new

    update_step(:starting)
    raise "SFTP connection isn't configured." unless @config.configured?

    update_step(:computing_diff)
    # A full push re-uploads every file and prunes host files removed locally —
    # recovers from a manifest that's drifted out of sync with the host.
    diff = full ? @manifest.full_diff : @manifest.diff
    if diff.empty?
      write_completed(message: "Already in sync — nothing to push.")
      return
    end

    update_step(:connecting)
    pusher = StaticSiteSync::Pusher.for(config: @config, progress_proc: progress_proc)

    update_step(:uploading)
    result = pusher.push!(diff)

    update_step(:recording_manifest)
    @manifest.record_partial_push!(
      uploaded_paths: result[:uploaded],
      deleted_paths:  result[:deleted]
    )

    update_step(:finishing)
    @config.update!(last_pushed_at: Time.current)

    write_completed(uploaded: result[:uploaded].size, deleted: result[:deleted].size)
  rescue => e
    Rails.logger.error "[StaticSiteSyncPushJob] failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    write_failed(e)
  end

  private

  def update_step(step)
    @last_step = step
    @progress  = nil
    Rails.logger.info "[StaticSiteSyncPushJob] step: #{step}"
    write_running_status
  end

  def progress_proc
    @progress_proc ||= ->(completed:, total:) {
      @progress = { completed: completed, total: total }
      write_running_status
    }
  end

  def write_running_status
    payload = {
      state:      :running,
      kind:       :push,
      step:       @last_step,
      started_at: @started_at
    }
    payload[:progress] = @progress if @progress
    write_status(payload)
  end

  def write_completed(uploaded: 0, deleted: 0, message: nil)
    write_status(
      state:        :completed,
      kind:         :push,
      completed_at: Time.current,
      uploaded:     uploaded,
      deleted:      deleted,
      message:      message
    )
  end

  def write_failed(error)
    write_status(
      state:    :failed,
      kind:     :push,
      step:     @last_step,
      error:    "#{error.class}: #{error.message}",
      failed_at: Time.current
    )
  end

  def write_status(data)
    Rails.cache.write(STATUS_CACHE_KEY, data, expires_in: STATUS_TTL)
  end
end
