require "test_helper"

# Quitting Roe mid-deploy hands the job back to the queue (Solid Queue's
# Process::Executor#release_all_claimed_executions runs on a clean shutdown),
# so the next boot can pick it up and deploy again with nobody watching. A
# deploy auto-commits the working tree, pushes secrets and builds an image —
# not something to resume silently hours later.
class DeployResumeGuardTest < ActiveSupport::TestCase
  KEY = PerformDeployJob::STATUS_CACHE_KEY

  setup    { Rails.cache.delete(KEY) }
  teardown { Rails.cache.delete(KEY) }

  def running(**overrides)
    Rails.cache.write(KEY, { state: :running, target: "fly", version_tag: "100",
                             started_at: Time.current, log: "" }.merge(overrides))
  end

  # The guard runs before anything else in perform, so a refusal is observable
  # as "prepare_version_file was never reached".
  def run_job(version_tag: "100")
    job = PerformDeployJob.new
    job.expects(:prepare_version_file).never
    job.perform(target: "fly", version_tag: version_tag)
  end

  def assert_job_proceeds(version_tag: "100")
    job = PerformDeployJob.new
    job.expects(:prepare_version_file).once
    job.stubs(:auto_commit)
    job.stubs(:sync_fly_secrets)
    job.stubs(:run_with_streaming)
    DeployPreflight.any_instance.stubs(:blockers).returns([])
    job.perform(target: "fly", version_tag: version_tag)
  end

  test "a fresh deploy runs" do
    running
    assert_job_proceeds
    assert Rails.cache.read(KEY)[:job_started_at], "the attempt is recorded"
  end

  test "a job re-queued by a restart refuses to deploy again" do
    running(job_started_at: 20.minutes.ago)
    run_job
  end

  test "a dismissed deploy doesn't run when the job comes back" do
    Rails.cache.delete(KEY)
    run_job
  end

  test "a superseded deploy doesn't run" do
    running(version_tag: "200")
    run_job(version_tag: "100")
  end
end
