# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# run_with_streaming read the deploy's output with each_line, which blocks
# forever on a command that never writes and never exits. A hung `kamal deploy`
# or `fly deploy` left the job running indefinitely: the page showed a deploy
# that never finished, never failed, and couldn't be recovered without
# restarting Roe.
#
# DeployWatchdog can't reach this one — it asks Solid Queue whether the job is
# alive, and a hung job is very much alive. The timeout has to be here.
class DeployStallTimeoutTest < ActiveJob::TestCase
  setup do
    @job = PerformDeployJob.new
    Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY)
  end

  teardown { Rails.cache.delete(PerformDeployJob::STATUS_CACHE_KEY) }

  def run_command(script, stall:)
    @job.stubs(:stall_timeout).returns(stall)
    @job.stubs(:term_grace).returns(0.2) # the real 2s grace isn't what's under test
    @job.send(:run_with_streaming, "sh -c '#{script}'", target: "kamal", version_tag: "v0")
    Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)
  end

  test "a command that goes quiet is stopped rather than waited on" do
    started = Time.current
    status = run_command("echo starting; sleep 30", stall: 1)

    assert_operator Time.current - started, :<, 15,
      "the job waited on the command instead of stopping it"
    assert_equal :failed, status[:state]
  end

  test "the failure says what happened, not just that it failed" do
    status = run_command("echo starting; sleep 30", stall: 1)

    assert_match "stopped responding", status[:error]
    assert_match "no output for", status[:error],
      "a bare 'deploy failed' sends someone looking through a log that ends mid-sentence"
  end

  test "the log collected before the stall is kept" do
    status = run_command("echo the-last-thing-it-did; sleep 30", stall: 1)

    assert_match "the-last-thing-it-did", status[:log],
      "on a stall this is the only evidence there is"
    assert_match PerformDeployJob::STALL_MARKER, status[:log]
  end

  # kamal and fly are front ends; the thing actually hung is usually a docker or
  # ssh grandchild. Killing only the parent orphans it, still holding whatever
  # it was holding.
  test "the whole process group is stopped, not just the command" do
    # Not Rails.root — this repo lives under a path containing "&" and spaces,
    # which an unquoted shell word splits into other commands. The touch then
    # never runs and the assertion passes whatever the kill did.
    marker = File.join(Dir.tmpdir, "zz-stall-grandchild-#{SecureRandom.hex(4)}")
    FileUtils.rm_f(marker)

    # The grandchild outlives its parent unless the group is signalled.
    run_command(%(echo go; (sleep 3; touch "#{marker}") & wait), stall: 1)
    sleep 4

    assert_not File.exist?(marker),
      "a grandchild survived the timeout — only the front-end process was killed"
  ensure
    FileUtils.rm_f(marker)
  end

  # The failure mode that matters most: killing a deploy that was working.
  test "a slow command that is still talking is left alone" do
    status = run_command("echo one; sleep 1; echo two; sleep 1; echo three", stall: 3)

    assert_equal :completed, status[:state],
      "output resets the clock — a quiet build stage must not read as a stall"
    assert_match "three", status[:log]
  end

  test "a command that fails normally is not reported as a stall" do
    status = run_command("echo nope; exit 1", stall: 5)

    assert_equal :failed, status[:state]
    assert_no_match(/stopped responding/, status[:error])
  end

  # An interrupted deploy leaves the target holding something it only releases
  # on a clean finish. Said at the point of interruption, because Fly's CLI is
  # a binary whose error text we can't read and so can't match on later.
  test "a stopped deploy warns about what it may have left behind" do
    @job.stubs(:stall_timeout).returns(1)
    @job.stubs(:term_grace).returns(0.2)
    @job.send(:run_with_streaming, "sh -c 'echo go; sleep 30'", target: "kamal", version_tag: "v0")

    assert_match "kamal lock release", Rails.cache.read(PerformDeployJob::STATUS_CACHE_KEY)[:error]
  end

  test "the leftover warning matches the target" do
    assert_match "fly machine leases clear", DeployWatchdog.cleanup_hint("fly")
    assert_match "kamal lock release", DeployWatchdog.cleanup_hint("kamal")
    assert_nil DeployWatchdog.cleanup_hint("something-else")
  end

  # Kamal's own wording, from Kamal::Cli::Base#raise_if_locked.
  test "a stale deploy lock is explained rather than shown raw" do
    diagnosis = DeployDiagnostics.for("Deploy lock already in place!\nDeploy lock found. Run 'kamal lock help' for more information")

    assert_equal "A previous deploy is still holding the lock", diagnosis[:title]
    assert_match "kamal lock release", diagnosis[:steps].join(" ")
  end

  # Every other signature matches what the failing command printed. A stall
  # prints nothing, so this one matches the marker Roe writes instead.
  test "the panel explains a stall rather than showing an empty log" do
    diagnosis = DeployDiagnostics.for("some output\n[#{PerformDeployJob::STALL_MARKER}] no output for 10 minutes")

    assert_equal "The deploy stopped responding", diagnosis[:title]
    assert_match "safe to deploy again", diagnosis[:steps].join(" ")
  end
end
