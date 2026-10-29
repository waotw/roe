# frozen_string_literal: true

# The things that have to be true before a deploy can work, checked before one
# starts rather than discovered several minutes in.
#
# A deploy that fails at minute four costs the same as one that fails at second
# zero, except you've watched a log the whole time and the error names Docker's
# plumbing rather than the thing you have to go and fix.
#
# Kamal checks Docker only, and deliberately. It's tempting to also test SSH to
# the deploy server, but Kamal reaches it through net-ssh using the key named
# in deploy.yml — not the `ssh` binary, and not your agent. Shelling out to
# `ssh` tests a path Kamal never takes and reports failures that have no
# bearing on whether a deploy would work. A check that cries wolf is worse than
# no check.
#
# Fly checks the CLI and the session. An expired Fly session is worse than a
# plain failure: `fly deploy` produces no output and never returns, so the
# deploy page sits there with an empty log and no way back.
class DeployPreflight
  # `key` names the message to show — its wording is in
  # app/views/admin/deploy_messages/_<key>.html.erb and its title in
  # DeployMessages. The title is kept here too because the deploy log and the
  # short error line are written before any page is.
  #
  # `blocking` distinguishes what stops a deploy from what's merely worth
  # saying. Nothing advisory exists yet; the field is here so that adding one
  # later doesn't mean adding a new way to refuse deploys by accident.
  Issue = Struct.new(:key, :blocking, keyword_init: true) do
    def title = DeployMessages.title(key)
  end

  # Docker Desktop takes a while to come up, so a short timeout would report a
  # starting daemon as a stopped one.
  DOCKER_TIMEOUT = 15

  # `fly auth whoami` is a network round trip to Fly's API.
  FLY_TIMEOUT = 20

  # flyctl couldn't reach Fly at all, rather than reaching it and being told no.
  # `EOF` is the one a user actually hit: the connection closed before Fly
  # answered. A timeout counts too — a hanging call is unreachable.
  NETWORK_TROUBLE = /
    :\ EOF
    |timed\ out
    |connection\ refused
    |no\ such\ host
    |network\ is\ unreachable
    |TLS\ handshake
    |i\/o\ timeout
    |certificate
    |dial\ tcp
    |context\ deadline\ exceeded
  /xi

  def self.for(target) = new.issues(target)
  def self.for_kamal = new.issues("kamal")
  def self.for_fly   = new.issues("fly")

  def issues(target = "kamal")
    target.to_s == "fly" ? [ fly_cli_issue || fly_auth_issue ].compact
                         : [ docker_issue ].compact
  end

  # What actually stops a deploy from starting.
  def blockers(target = "kamal") = issues(target).select(&:blocking)

  # Kamal builds the image through the local Docker daemon. With it stopped the
  # build can't run, and what Kamal reports is whatever it failed to reach
  # next — usually the remote builder over SSH, which reads as a problem with
  # the server rather than with this computer.
  def docker_issue
    return nil if docker_running?

    Issue.new(key: "docker_not_running", blocking: true)
  end

  # No CLI, nothing to deploy with. Separate from the auth check because the
  # remedy is different and asking `fly auth whoami` without a `fly` binary
  # would report "not signed in", which sends someone to log in to a tool they
  # haven't installed.
  def fly_cli_issue
    return nil if fly_cli?

    Issue.new(key: "fly_cli_missing", blocking: true)
  end

  # An expired Fly session is the reason this check exists.
  #
  # `fly deploy` with a dead session produces no output and doesn't return — so
  # the deploy page sits with an empty log, no progress and no failure, and
  # there's nothing to read that would tell you why. Catching it here turns a
  # hang into a sentence.
  #
  # Reaching Fly failed outright is told apart from being signed out: telling
  # someone to sign in would send them to a command that fails the same way —
  # the login and the check use the same connection.
  def fly_auth_issue
    case fly_auth_state
    when :ok          then nil
    when :unreachable then Issue.new(key: "fly_unreachable", blocking: true)
    else                   Issue.new(key: "fly_signed_out", blocking: true)
    end
  end

  def fly_cli? = run("which", "fly", timeout: 5)

  def fly_authenticated? = fly_auth_state == :ok

  # :ok, :signed_out, or :unreachable.
  #
  # `fly auth whoami` fails for two quite different reasons and the remedies
  # are opposites. Signed out: run `fly auth login`. Can't reach Fly's API:
  # running `fly auth login` fails the same way, so telling someone to do it
  # sends them round in a circle — which is exactly what happened to a user
  # whose login died with `Post "https://api.fly.io/api/v1/cli_sessions": EOF`.
  #
  # Classified from the output because the exit status is 1 either way.
  def fly_auth_state
    ok, output = run_capture("fly", "auth", "whoami", timeout: FLY_TIMEOUT)
    return :ok if ok

    NETWORK_TROUBLE.match?(output) ? :unreachable : :signed_out
  end

  def docker_running?
    run("docker", "version", "--format", "{{.Server.Version}}", timeout: DOCKER_TIMEOUT)
  end

  private

  # A check that hangs is worse than one that fails, so it's bounded, and
  # anything unexpected counts as "couldn't verify" rather than raising into
  # the deploy.
  def run(*command, timeout:)
    run_capture(*command, timeout: timeout).first
  end

  # [success, output]. A timeout counts as unreachable rather than as a failure
  # with no output, since that's what a hanging network call looks like.
  def run_capture(*command, timeout:)
    Bundler.with_original_env do
      Timeout.timeout(timeout) do
        out, status = Open3.capture2e(*command)
        [ status.success?, out.to_s ]
      end
    end
  rescue Timeout::Error
    [ false, "timed out" ]
  rescue Errno::ENOENT, StandardError => e
    [ false, e.message.to_s ]
  end
end
