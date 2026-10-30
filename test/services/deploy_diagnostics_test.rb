# frozen_string_literal: true

require "test_helper"

# Kamal and Docker name the mechanism that failed, not the thing to fix. These
# assert the translation — that a real log names the right message, that the
# message reads right with this site's details filled in, and that an
# unrecognised log still gets something to do next.
class DeployDiagnosticsTest < ActiveSupport::TestCase
  include DeployMessageHelper

  # The log that started this: the remote builder's SSH connection refused.
  SSH_FAILURE = <<~LOG
    dev.roecms.com docker system dial-stdio] has exited with exit status 255, make sure
    the URL is valid, and Docker 18.09 or later is installed on the remote host:
    stderr=root@dev.roecms.com: Permission denied (publickey).
    docker stderr: Nothing written
  LOG

  def shown(diagnosis) = deploy_message_text(diagnosis.key, **diagnosis.locals)

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

    assert_equal "docker_not_running", d.key
    assert_equal "Docker isn't running on this computer", d.title
    assert_match "Docker Desktop", shown(d)
    assert_no_match(/ssh\/config|IdentityFile/, shown(d), "don't send them to fix SSH for a Docker problem")
  end

  test "the bare daemon error says the same thing" do
    assert_equal "docker_not_running", DeployDiagnostics.for("Cannot connect to the Docker daemon at unix:///var/run/docker.sock.").key
  end

  # The point of the message: commands you can copy, not adapt.
  test "the commands carry this site's own host" do
    d = DeployDiagnostics.for("Host key verification failed.", host: "dev.roecms.com", user: "root")

    assert_includes shown(d), "ssh root@dev.roecms.com"
    assert_includes shown(d), "ssh-keygen -R dev.roecms.com"
  end

  test "an unknown host falls back to a placeholder rather than blowing up" do
    assert_includes shown(DeployDiagnostics.for("Host key verification failed.")), "your-server.com"
  end

  test "shell snippets with quotes survive" do
    d = DeployDiagnostics.for("no space left on device", host: "h")

    assert_includes shown(d), "ssh root@h 'docker system prune -af'"
  end

  test "each signature is recognised" do
    {
      "Host key verification failed."                         => "server_identity",
      "ssh: Could not resolve hostname nope.example"          => "server_not_found",
      "ssh: connect to host x port 22: Connection timed out"  => "server_no_answer",
      "unauthorized: authentication required"                 => "registry_login",
      "write /var/lib/docker: no space left on device"        => "server_disk_full",
      "Deploy lock already in place!"                         => "deploy_lock_held",
      "[roe: deploy stalled] no output for 10 minutes"        => "deploy_stalled"
    }.each do |log, expected|
      d = DeployDiagnostics.for(log)

      assert_not_nil d, "#{log.inspect} matched nothing"
      assert_equal expected, d.key, "#{log.inspect} matched the wrong signature"
    end
  end

  # Every message someone can be shown has to tell them what to do next, and
  # end in a link — or, on Settings, a page to reload.
  test "every message renders, with a title and a next step, in every place it can appear" do
    DeployMessages::TITLES.each_key do |key|
      %i[settings before during].each do |context|
        text = deploy_message_text(key, context: context)

        assert_includes text, DeployMessages.title(key), "#{key} (#{context}) lost its heading"
        assert_match(/deploy again|reload this page|Troubleshooting → Deployment/i, text,
                     "#{key} (#{context}) explains but doesn't say what to do next")
      end
    end
  end

  test "every log signature names a message that exists" do
    DeployDiagnostics::SIGNATURES.each do |signature|
      assert DeployMessages.known?(signature[:key]), "#{signature[:key]} has no title"
      assert_nothing_raised { deploy_message_html(signature[:key]) }
    end
  end

  # The links are relative so they work offline and match the running version.
  # A link to an anchor the page doesn't have lands at the top, silently.
  test "every troubleshooting link points at a section the page has" do
    doc = Rails.root.join("lib/site_templates/minimum/documentation/roe/troubleshooting_deploy.md").read
    anchors = doc.scan(/\{: #([\w-]+)\}/).flatten +
              doc.scan(/^#+ (.+)$/).flatten.map { |h| h.downcase.gsub(/[^\w\s-]/, "").strip.gsub(/\s/, "-") }

    DeployMessages::TITLES.each_key do |key|
      %i[settings before during].each do |context|
        %w[kamal fly].each do |target|
          deploy_message_html(key, context: context, target: target)
            .scan(%r{/documentation/roe/troubleshoot-deployment#([\w-]+)}).flatten.each do |anchor|
            assert_includes anchors, anchor, "#{key} links to ##{anchor}, which the page doesn't have"
          end
        end
      end
    end
  end

  test "the dial-stdio wording alone is enough" do
    assert_equal "docker_not_running", DeployDiagnostics.for("docker system dial-stdio] has exited with exit status 255").key
  end

  test "the error field is read as well as the log" do
    assert_not_nil DeployDiagnostics.for("", "Host key verification failed.")
  end

  # ── Which messages a failed deploy shows ────────────────────────────────────

  def failed(**fields) = { state: :failed, target: "kamal", log: "", error: nil }.merge(fields)

  test "a deploy the checks stopped shows those checks, as stopped before it started" do
    messages = DeployDiagnostics.messages_for(failed(target: "fly", preflight: [ { key: "fly_signed_out", title: "x" } ]))

    assert_equal [ [ "fly_signed_out", :before ] ], messages.map { |m| [ m[:key], m[:context] ] }
  end

  test "a deploy Roe lost track of says so, for its own target" do
    messages = DeployDiagnostics.messages_for(failed(target: "fly", abandoned: true, log: "Host key verification failed."))

    assert_equal [ "deploy_interrupted" ], messages.map { |m| m[:key] }
    assert_includes deploy_message_text("deploy_interrupted", **messages.first[:locals]), "fly machine leases clear"
  end

  test "a failure in the log shows its message" do
    assert_equal [ "server_disk_full" ], DeployDiagnostics.messages_for(failed(log: "no space left on device")).map { |m| m[:key] }
  end

  test "a failure nothing recognises still gets a next step" do
    assert_equal [ "unrecognised" ], DeployDiagnostics.messages_for(failed(log: "something new")).map { |m| m[:key] }
  end

  test "a deploy that hasn't failed shows nothing" do
    assert_empty DeployDiagnostics.messages_for({ state: :running })
    assert_empty DeployDiagnostics.messages_for(nil)
  end

  # Saved by a Roe from before messages had names: the page shows its saved
  # wording instead, so nothing is listed here for it.
  test "an old preflight entry without a name is left to its saved wording" do
    old = failed(preflight: [ { title: "Docker isn't running", explanation: "…", steps: [ "Open Docker" ] } ])

    assert_empty DeployDiagnostics.messages_for(old)
  end
end
