# frozen_string_literal: true

require "test_helper"

# The failure panel offers a cold build after two failures in a row, so the
# count has to survive a retry. Every non-zero exit writes the same error
# string, which is why this is counted rather than compared by content.
class DeployFailureCountTest < ActiveSupport::TestCase
  setup { Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY) }
  teardown { Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY) }

  def job = @job ||= PerformDeployJob.new

  def status = Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)

  def fail!
    job.send(:write_status, state: :failed, target: "kamal", log: "x", error: "nope")
  end

  test "the first failure counts as one" do
    fail!

    assert_equal 1, status[:consecutive_failures]
    assert_not DeployDiagnostics.cache_suspect?(status)
  end

  # A retry writes :running in between, and the count has to carry through it.
  test "a failure after a retry counts as two" do
    fail!
    job.send(:write_status, state: :running, target: "kamal", log: "")
    assert_equal 1, status[:consecutive_failures], "the count was lost on retry"

    fail!

    assert_equal 2, status[:consecutive_failures]
    assert DeployDiagnostics.cache_suspect?(status), "a cold build should be offered by now"
  end

  test "a success clears the count" do
    fail!
    fail!
    job.send(:write_status, state: :completed, target: "kamal", log: "", completed_at: Time.current)

    assert_equal 0, status[:consecutive_failures]
    assert_not DeployDiagnostics.cache_suspect?(status)
  end

  # Dismissing a failed deploy deletes the key outright, so the next failure
  # starts from one again.
  test "dismissing clears the count" do
    fail!
    fail!
    Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY)
    fail!

    assert_equal 1, status[:consecutive_failures]
  end

  test "a cache-shaped log is suspect on the first failure" do
    assert DeployDiagnostics.cache_suspect?(
      { consecutive_failures: 1, log: "failed to compute cache key: not found" }
    )
  end

  # Repeating a diagnosed failure doesn't make it a cache problem. Docker off
  # twice is Docker off, and the cold build would be several wasted minutes.
  test "a diagnosed failure stays diagnosed however often it repeats" do
    assert_not DeployDiagnostics.cache_suspect?(
      { consecutive_failures: 5, log: "Cannot connect to the Docker daemon" }
    )
  end

  # But an unreadable one gets the escape hatch, which is the whole point of
  # counting.
  test "an undiagnosed failure repeated does become suspect" do
    assert DeployDiagnostics.cache_suspect?(
      { consecutive_failures: 2, log: "something we've never seen before" }
    )
  end

  test "an ordinary first failure isn't" do
    assert_not DeployDiagnostics.cache_suspect?(
      { consecutive_failures: 1, log: "Cannot connect to the Docker daemon" }
    )
  end

  test "no status at all isn't suspect" do
    assert_not DeployDiagnostics.cache_suspect?(nil)
    assert_not DeployDiagnostics.cache_suspect?({})
  end
end
