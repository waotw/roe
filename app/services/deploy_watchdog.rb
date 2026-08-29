# frozen_string_literal: true

# Reconciles the deploy status against whether a deploy is actually running.
#
# The status the Updates page renders lives in Rails.cache — Solid Cache in
# every environment, so it's a row in the database, not memory. Only
# PerformDeployJob ever writes the ending. Kill the process mid-deploy and
# there's nobody left to write it, so the row stays `state: :running` for its
# full 24-hour TTL and the page animates a spinner at nothing.
#
# Restarting doesn't help, which is the part that surprises people: a restart
# clears memory, and this was never in memory. One user sat on "Deploy in
# progress" for a day across several restarts, with `ps` showing no deploy
# process at all.
#
# Solid Queue already handled its half correctly. When the supervisor comes
# back it prunes the dead worker and fails the orphaned job
# (ClaimedExecution.orphaned.fail_all_with). Nothing connected that back to the
# cache. This is that connection.
#
# Authoritative, not heuristic. The tempting check is "no log output for N
# minutes = stuck", but a quiet `docker build` can go minutes without printing
# a line, and a check that cries wolf mid-deploy is worse than no check —
# it would tell people a working deploy had died. So this asks Solid Queue
# whether the job still exists instead of guessing from the log.
class DeployWatchdog
  # perform_later writes the job row inside the request that writes :running,
  # so the two are visible together almost immediately. The grace period is
  # for the gap around that write and for a queue that's briefly wedged —
  # cheap insurance against declaring a deploy dead a second after it started.
  GRACE = 2.minutes

  ABANDONED_MESSAGE =
    "Roe stopped before this deploy finished — usually because Roe was quit or " \
    "restarted while it was running. Nothing was left running in the background. " \
    "It's safe to deploy again."

  # Read the deploy status, correcting it first if it's describing a deploy
  # that isn't happening. Every reader goes through here so there's one
  # definition of "is a deploy running" rather than one per caller.
  def self.status
    new.reconciled_status
  end

  def reconciled_status
    status = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
    return status unless abandoned?(status)

    Rails.logger.warn "[DeployWatchdog] Marking abandoned deploy as failed (no live job)"

    failed = status.merge(
      state:        :failed,
      completed_at: Time.current,
      error:        ABANDONED_MESSAGE,
      abandoned:    true
    )
    Rails.cache.write(PerformDeployJob::STATUS_CACHE_KEY, failed, expires_in: PerformDeployJob::STATUS_TTL)
    failed
  end

  # A status claiming to be running with no job behind it to run it.
  def abandoned?(status)
    return false unless status.is_a?(Hash) && status[:state] == :running
    return false unless past_grace?(status)

    !live_job?
  end

  private

  # Without a started_at we can't tell a stalled deploy from one that began a
  # moment ago, so leave it alone. The TTL still bounds it.
  def past_grace?(status)
    started = status[:started_at]
    started.present? && started < GRACE.ago
  end

  # A deploy job Solid Queue still intends to run.
  #
  # `finished_at` is set only on success (Job::Executable#finished!), so a
  # failed job also reads as unfinished — which is exactly the state the
  # supervisor leaves an orphaned deploy in. Excluding jobs with a
  # failed_execution is what separates "still queued" from "already given up
  # on", and that distinction is the whole check.
  #
  # Anything unexpected here counts as "a deploy is running". Being wrong in
  # that direction leaves the status alone; being wrong the other way would
  # tell someone their live deploy had died.
  def live_job?
    SolidQueue::Job
      .where(class_name: "PerformDeployJob", finished_at: nil)
      .where.missing(:failed_execution)
      .exists?
  rescue StandardError => e
    Rails.logger.warn "[DeployWatchdog] Couldn't check the job queue (#{e.message}) — assuming a deploy is running"
    true
  end
end
