# frozen_string_literal: true

require "test_helper"

# Kamal and Docker name the mechanism that failed, not the thing to fix. These
# assert the translation — that a real log produces the right explanation, and
# that an unrecognised one produces none rather than a confident wrong guess.
class DeployDiagnosticsTest < ActiveSupport::TestCase
  # The log that started this: the remote builder's SSH connection refused.
  SSH_FAILURE = <<~LOG
    dev.roecms.com docker system dial-stdio] has exited with exit status 255, make sure
    the URL is valid, and Docker 18.09 or later is installed on the remote host:
    stderr=root@dev.roecms.com: Permission denied (publickey).
    docker stderr: Nothing written
  LOG

  test "an unrecognised failure gets no diagnosis" do
    assert_nil DeployDiagnostics.for("Something went wrong in a way we've never seen")
  end

  test "an empty log gets no diagnosis" do
    assert_nil DeployDiagnostics.for("")
    assert_nil DeployDiagnostics.for(nil)
    assert_nil DeployDiagnostics.for_status(nil)
  end

  # This reads like an SSH problem and isn't. Docker only reaches for the remote
  # builder because the local daemon wasn't there to build with, so the useful
  # answer is "start Docker" — not "edit ~/.ssh/config", which would send
  # someone to fix a path they don't use and may never have set up.
  test "the dial-stdio refusal is reported as Docker being down" do
    d = DeployDiagnostics.for(SSH_FAILURE)

    assert_equal "Docker isn't running on this computer", d.title
    assert_match "Docker Desktop", d.steps.join("\n")
    assert_no_match(/ssh\/config|IdentityFile/, d.steps.join("\n"),
                    "don't send them to fix SSH for a Docker problem")
  end

  test "the bare daemon error says the same thing" do
    d = DeployDiagnostics.for("Cannot connect to the Docker daemon at unix:///var/run/docker.sock.")

    assert_equal "Docker isn't running on this computer", d.title
  end

  # The point of the panel: commands you can copy, not adapt.
  test "the steps carry this site's own host" do
    d = DeployDiagnostics.for("Host key verification failed.", host: "dev.roecms.com", user: "root")
    steps = d.steps.join("\n")

    assert_match "dev.roecms.com", steps
    assert_no_match(/%\{/, steps, "a placeholder was left unfilled")
  end

  test "an unknown host falls back to a placeholder rather than blowing up" do
    d = DeployDiagnostics.for("Host key verification failed.")

    assert_no_match(/%\{/, d.steps.join("\n"))
    assert_match "your-server.com", d.steps.join("\n")
  end

  # `format` would choke on the % and braces in shell snippets; this is the
  # regression guard for that.
  test "shell snippets with braces and percent signs survive" do
    d = DeployDiagnostics.for("no space left on device", host: "h")

    assert_match "docker system prune -af", d.steps.join("\n")
  end

  test "each signature is recognised" do
    {
      "Host key verification failed."                => "identity isn't recognised",
      "ssh: Could not resolve hostname nope.example" => "address couldn't be found",
      "ssh: connect to host x port 22: Connection timed out" => "didn't answer",
      "unauthorized: authentication required"        => "registry rejected",
      "write /var/lib/docker: no space left on device" => "run out of disk space"
    }.each do |log, expected|
      d = DeployDiagnostics.for(log)

      assert_not_nil d, "#{log.inspect} matched nothing"
      assert_match expected, d.title, "#{log.inspect} matched the wrong signature"
    end
  end

  test "every signature offers at least one step" do
    DeployDiagnostics::SIGNATURES.each do |signature|
      assert signature[:steps].any?, "#{signature[:title]} explains but doesn't help"
      assert signature[:title].present?
      assert signature[:explanation].present?
    end
  end

  test "the dial-stdio wording alone is enough" do
    d = DeployDiagnostics.for("docker system dial-stdio] has exited with exit status 255")

    assert_equal "Docker isn't running on this computer", d.title
  end

  test "the error field is read as well as the log" do
    assert_not_nil DeployDiagnostics.for("", "Host key verification failed.")
  end
end
