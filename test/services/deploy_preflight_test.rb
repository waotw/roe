# frozen_string_literal: true

require "test_helper"

# Checked before a deploy starts rather than discovered four minutes in. A
# stopped local Docker surfaces as "Permission denied (publickey)" against the
# deploy server, which reads as a problem with the server and isn't.
class DeployPreflightTest < ActiveSupport::TestCase
  test "nothing to report when Docker is up" do
    preflight = DeployPreflight.new
    preflight.stubs(:docker_running?).returns(true)

    assert_empty preflight.issues
  end

  # Kamal reaches the server through net-ssh with the key from deploy.yml, not
  # the `ssh` binary and not an agent. A check that shelled out to `ssh` failed
  # on a working setup and would have sent someone editing ~/.ssh/config for
  # nothing. Don't put it back.
  test "nothing here tests SSH" do
    assert_not DeployPreflight.new.respond_to?(:ssh_works?)
    assert_not DeployPreflight.method_defined?(:ssh_issue)
  end

  # The same problem reached two ways — caught beforehand, or read off a failed
  # log — has to read the same either way. It was duplicated in both files and
  # only stayed in step by luck.
  test "the wording comes from the one place deploy messages live" do
    preflight = DeployPreflight.new
    preflight.stubs(:docker_running?).returns(false)
    issue = preflight.docker_issue
    from_log = DeployDiagnostics.for("Cannot connect to the Docker daemon")

    assert_equal from_log.title, issue.title
    assert_equal from_log.explanation, issue.explanation
    assert_equal from_log.steps, issue.steps
  end

  test "a stopped Docker is reported in terms of this computer, not the server" do
    preflight = DeployPreflight.new
    preflight.stubs(:docker_running?).returns(false)

    issue = preflight.docker_issue

    assert_match(/Docker isn't running/, issue.title)
    assert_match(/this computer/, issue.title + issue.explanation)
    assert issue.steps.any?
  end

  # A check that hangs is worse than one that fails.
  test "a command that doesn't exist counts as failed, not an exception" do
    preflight = DeployPreflight.new

    assert_nothing_raised do
      assert_not preflight.send(:run, "definitely-not-a-real-command-xyz", timeout: 5)
    end
  end

  test "a stopped Docker does stop the deploy" do
    preflight = DeployPreflight.new
    preflight.stubs(:docker_running?).returns(false)

    assert_equal 1, preflight.blockers.size
    assert_match(/Docker isn't running/, preflight.blockers.first.title)
  end

end
