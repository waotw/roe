require "test_helper"

class DeployWatchdogTest < ActiveSupport::TestCase
  KEY = PerformDeployJob::STATUS_CACHE_KEY

  setup do
    Rails.cache.delete(KEY)
    SolidQueue::Job.where(class_name: "PerformDeployJob").destroy_all
  end

  teardown do
    Rails.cache.delete(KEY)
    SolidQueue::Job.where(class_name: "PerformDeployJob").destroy_all
  end

  def write_running(started_at:)
    Rails.cache.write(KEY, { state: :running, target: "fly", version_tag: "1", started_at: started_at, log: "" })
  end

  def queue_job(failed: false)
    job = SolidQueue::Job.create!(class_name: "PerformDeployJob", queue_name: "default", arguments: "{}")
    SolidQueue::FailedExecution.create!(job: job, error: "boom") if failed
    job
  end

  test "a deploy with a job still queued is left alone" do
    write_running(started_at: 1.hour.ago)
    queue_job

    assert_equal :running, DeployWatchdog.status[:state]
  end

  # The case that stranded a real user: Roe was quit mid-deploy, Solid Queue's
  # supervisor failed the orphaned job on the next boot, and nothing told the
  # cache. `ps` showed no deploy running for a day.
  test "a running deploy with no job behind it is marked failed" do
    write_running(started_at: 1.day.ago)

    status = DeployWatchdog.status

    assert_equal :failed, status[:state]
    assert status[:abandoned]
    assert_match "quit or restarted", status[:error]
    assert_equal :failed, Rails.cache.read(KEY)[:state], "the correction is persisted, not just returned"
  end

  # A failed job keeps finished_at nil, so "unfinished" alone would read it as
  # alive and leave the page stuck forever — which is the exact bug.
  test "a job the supervisor already failed doesn't count as alive" do
    write_running(started_at: 1.day.ago)
    queue_job(failed: true)

    assert_equal :failed, DeployWatchdog.status[:state]
  end

  test "a deploy that just started is inside the grace period" do
    write_running(started_at: 10.seconds.ago)

    assert_equal :running, DeployWatchdog.status[:state],
      "a deploy enqueued moments ago must not be declared dead"
  end

  test "a finished deploy is untouched" do
    Rails.cache.write(KEY, { state: :completed, target: "fly", completed_at: Time.current })

    assert_equal :completed, DeployWatchdog.status[:state]
  end

  test "no status stays no status" do
    assert_nil DeployWatchdog.status
  end

  # Being wrong here in the other direction would tell someone their live
  # deploy had died, so an unreadable queue means "leave it running".
  test "an unreadable queue leaves the status alone" do
    write_running(started_at: 1.day.ago)
    SolidQueue::Job.stubs(:where).raises(StandardError, "no such table")

    state = DeployWatchdog.status[:state]
    SolidQueue::Job.unstub(:where)  # teardown needs the real one back

    assert_equal :running, state
  end
end
