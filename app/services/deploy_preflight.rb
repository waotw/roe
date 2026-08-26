# frozen_string_literal: true

# The things that have to be true before a Kamal deploy can work, checked
# before one starts rather than discovered several minutes in.
#
# A deploy that fails at minute four costs the same as one that fails at second
# zero, except you've watched a log the whole time and the error names Docker's
# plumbing rather than the thing you have to go and fix.
#
# Only Docker for now, and deliberately. It's tempting to also test SSH to the
# deploy server, but Kamal reaches it through net-ssh using the key named in
# deploy.yml — not the `ssh` binary, and not your agent. Shelling out to `ssh`
# tests a path Kamal never takes and reports failures that have no bearing on
# whether a deploy would work. A check that cries wolf is worse than no check.
class DeployPreflight
  # `blocking` distinguishes what stops a deploy from what's merely worth
  # saying. Nothing advisory exists yet; the field is here so that adding one
  # later doesn't mean adding a new way to refuse deploys by accident.
  Issue = Struct.new(:title, :explanation, :steps, :blocking, keyword_init: true)

  # Docker Desktop takes a while to come up, so a short timeout would report a
  # starting daemon as a stopped one.
  DOCKER_TIMEOUT = 15

  def self.for_kamal = new.issues

  def issues = [ docker_issue ].compact

  # What actually stops a deploy from starting.
  def blockers = issues.select(&:blocking)

  # Kamal builds the image through the local Docker daemon. With it stopped the
  # build can't run, and what Kamal reports is whatever it failed to reach
  # next — usually the remote builder over SSH, which reads as a problem with
  # the server rather than with this computer.
  def docker_issue
    return nil if docker_running?

    # Same wording whether we catch this beforehand or read it off a failed
    # log, so it's written once, in DeployDiagnostics with every other deploy
    # message. Two copies would drift, and the two paths are the same problem.
    message = DeployDiagnostics::DOCKER_DOWN

    Issue.new(
      title:       message[:title],
      explanation: message[:explanation],
      steps:       message[:steps],
      blocking:    true
    )
  end

  def docker_running?
    run("docker", "version", "--format", "{{.Server.Version}}", timeout: DOCKER_TIMEOUT)
  end

  private

  # A check that hangs is worse than one that fails, so it's bounded, and
  # anything unexpected counts as "couldn't verify" rather than raising into
  # the deploy.
  def run(*command, timeout:)
    Bundler.with_original_env do
      Timeout.timeout(timeout) do
        _out, status = Open3.capture2e(*command)
        status.success?
      end
    end
  rescue Timeout::Error, Errno::ENOENT, StandardError
    false
  end
end
