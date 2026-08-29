# frozen_string_literal: true

require "test_helper"

# An expired Fly session is worse than a plain failure: `fly deploy` produces no
# output and never returns, so the deploy page sits with an empty log, no
# progress and no way back. There's nothing to read that would say why.
class FlyPreflightTest < ActiveSupport::TestCase
  def preflight = @preflight ||= DeployPreflight.new

  test "a signed-in Fly install has nothing to report" do
    preflight.stubs(:fly_cli?).returns(true)
    preflight.stubs(:fly_auth_state).returns(:ok)

    assert_empty preflight.issues("fly")
  end

  test "an expired session blocks the deploy and says how to fix it" do
    preflight.stubs(:fly_cli?).returns(true)
    preflight.stubs(:fly_auth_state).returns(:signed_out)

    issue = preflight.issues("fly").sole

    assert_match(/not signed in to Fly/i, issue.title)
    assert issue.blocking, "a hang is not something to warn about and continue past"
    assert_match(/fly auth login/, issue.steps.join(" "))
  end

  # Asking `fly auth whoami` without a `fly` binary reports "not signed in",
  # which would send someone to log in to a tool they haven't installed.
  test "a missing CLI is reported as missing, not as signed out" do
    preflight.stubs(:fly_cli?).returns(false)
    preflight.expects(:fly_auth_state).never

    issue = preflight.issues("fly").sole

    assert_match(/isn't installed/i, issue.title)
    assert_match(/brew install flyctl/, issue.steps.join(" "))
  end

  test "the Fly checks don't run for a Kamal deploy" do
    preflight.stubs(:docker_running?).returns(true)
    preflight.expects(:fly_cli?).never
    preflight.expects(:fly_auth_state).never

    assert_empty preflight.issues("kamal")
  end

  test "Docker isn't checked for a Fly deploy" do
    preflight.stubs(:fly_cli?).returns(true)
    preflight.stubs(:fly_auth_state).returns(:ok)
    preflight.expects(:docker_running?).never

    preflight.issues("fly")
  end

  test "blockers are target-aware too" do
    preflight.stubs(:fly_cli?).returns(true)
    preflight.stubs(:fly_auth_state).returns(:signed_out)

    assert_equal 1, preflight.blockers("fly").size
  end

  # ── Signed out vs unreachable ────────────────────────────────────────────
  #
  # `fly auth whoami` exits 1 for both, but the remedies are opposites. A user
  # whose login died with `Post ".../cli_sessions": EOF` would have been told
  # to run `fly auth login` — the very command that was failing.

  def with_whoami(output, ok: false)
    preflight.define_singleton_method(:run_capture) { |*_a, **_k| [ ok, output ] }
    preflight.define_singleton_method(:fly_cli?) { true }
    preflight
  end

  test "a network failure is reported as unreachable, not as signed out" do
    issue = with_whoami('Error: Post "https://api.fly.io/api/v1/cli_sessions": EOF').issues("fly").sole

    assert_match(/couldn't reach Fly/i, issue.title)
    assert_no_match(/fly auth login/, issue.steps.join(" "),
      "that's the command that just failed — it would loop them")
    assert_match(/status\.fly\.io/, issue.steps.join(" "))
  end

  test "a timeout counts as unreachable" do
    assert_match(/couldn't reach Fly/i, with_whoami("timed out").issues("fly").sole.title)
  end

  test "DNS failure counts as unreachable" do
    issue = with_whoami("dial tcp: lookup api.fly.io: no such host").issues("fly").sole

    assert_match(/couldn't reach Fly/i, issue.title)
  end

  # The distinction has to survive: a genuine sign-out still gets the login steps.
  test "a real sign-out still says to sign in" do
    issue = with_whoami("Error: failed retrieving current user: You must be authenticated to view this.")
              .issues("fly").sole

    assert_match(/not signed in/i, issue.title)
    assert_match(/fly auth login/, issue.steps.join(" "))
  end

  test "a working session reports nothing either way" do
    assert_empty with_whoami("ben@example.com", ok: true).issues("fly")
  end

  # ── The log-reading safety net, for a session that dies mid-deploy ────────

  test "Fly's own wording is recognised in a log" do
    d = DeployDiagnostics.for("Error: failed retrieving current user: ... You must be authenticated to view this.")

    assert_equal "Your Fly session has expired", d.title
    assert_match(/fly auth login/, d.steps.join(" "))
  end

  # A generic /authenticat/ match would also catch this and, sitting above it,
  # would answer a Kamal registry problem with "run fly auth login".
  test "a registry rejection is still a registry rejection" do
    d = DeployDiagnostics.for("ERROR: failed to solve: unauthorized: authentication required")

    assert_equal "The image registry rejected your login", d.title
  end

  test "an unreachable-Fly log is recognised, and not as a sign-out" do
    d = DeployDiagnostics.for('Error: Post "https://api.fly.io/api/v1/cli_sessions": EOF')

    assert_equal "Roe couldn't reach Fly", d.title
  end

  # ── The docs deep link ───────────────────────────────────────────────────
  #
  # Relative, not go-roe.com: the documentation ships with every install, so it
  # works offline and matches the version running. And when the diagnosis is
  # "we can't reach the network", an external link is the one most likely to
  # fail too.

  test "the unreachable message links into the troubleshooting docs" do
    steps = with_whoami('Error: Post "https://api.fly.io/api/v1/cli_sessions": EOF')
              .issues("fly").sole.steps.join(" ")

    assert_match %r{/documentation/roe/troubleshoot-deployment\#fly-unreachable}, steps
    assert_no_match(/go-roe\.com/, steps, "an external link is exactly what may not load here")
  end

  test "the signed-out message links to its own section" do
    steps = with_whoami("You must be authenticated to view this").issues("fly").sole.steps.join(" ")

    assert_match %r{/documentation/roe/troubleshoot-deployment\#fly-signed-out}, steps
  end

  # The doc sets these anchors explicitly, so rewording a heading can't quietly
  # break the links.
  test "the docs carry the anchors the admin points at" do
    doc = Rails.root.join("..", "site", "documentation", "roe", "troubleshooting_deploy.md")
    skip "docs live outside the app in this checkout" unless File.exist?(doc)

    body = File.read(doc)
    assert_match(/\{:\s*#fly-unreachable\s*\}/, body)
    assert_match(/\{:\s*#fly-signed-out\s*\}/, body)
  end

  # Steps are rendered through sanitize; without `a` in the allowed tags the
  # link is silently stripped and the step reads as bare text.
  test "the deploy panel lets links through" do
    panel = File.read(Rails.root.join("app", "views", "admin", "updates", "_deploy_active.html.erb"))
    # Whole lines: a character-class scan stops at the `%` in `%w[...]` and
    # captures nothing useful.
    sanitizers = panel.lines.select { |l| l.include?("sanitize step") }

    assert sanitizers.any?, "couldn't find the step sanitizer"
    sanitizers.each { |s| assert_match(/tags:.*\ba\b/, s, "links would be stripped: #{s}") }
  end

  test "the deploy job preflights whichever target is deploying" do
    source = File.read(Rails.root.join("app", "jobs", "perform_deploy_job.rb"))

    assert_match(/DeployPreflight\.new\.blockers\(target\)/, source,
      "the preflight was Kamal-only; a Fly deploy skipped it entirely")
  end
end
