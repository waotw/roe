# frozen_string_literal: true

# Reads a failed deploy's log and says, in plain terms, what went wrong.
#
# Kamal and Docker report failures in their own vocabulary — `docker system
# dial-stdio has exited with exit status 255` names the mechanism that failed,
# not the thing you have to go and fix. Someone deploying their own site once a
# month has no way to translate that.
#
# So: match the handful of failures that actually recur, and for each one say
# what happened, why, and the command that fixes it. Everything unmatched falls
# through to the raw log, which is what was there before — this only ever adds.
#
# Ordered most specific first; the first match wins. A signature that could
# match another's log has to come before it.
class DeployDiagnostics
  Diagnosis = Struct.new(:title, :explanation, :steps, :docs, keyword_init: true)

  # `docker system dial-stdio` is the remote builder connecting over SSH. It
  # shells out to the plain `ssh` binary, which — unlike Kamal — never reads
  # the `ssh.keys` setting in config/deploy.yml. So a deploy key that works for
  # Kamal is invisible here, and the connection falls back to your default
  # identities and is refused.
  #
  # It bites hardest from inside Roe: the Rails process usually has no
  # SSH_AUTH_SOCK, so there's no agent to fall back on either, and the same
  # deploy run by hand from a terminal succeeds.
  SSH_AUTH = {
    match: /Permission denied \(publickey\)|dial-stdio.*exit status 255/mi,
    title: "The deploy server refused the SSH connection",
    explanation:
      "Docker connects to your server over SSH to build the image, and it uses the " \
      "plain <code>ssh</code> command rather than the key named in " \
      "<code>config/deploy.yml</code>. If that key isn't offered by default, the " \
      "server turns the connection away. This often works from a terminal and fails " \
      "here, because Roe runs without access to your SSH agent.",
    steps: [
      "Add the host to <code>~/.ssh/config</code> so every SSH connection uses the right key:",
      "<pre>Host %{host}\n  User %{user}\n  IdentityFile %{key}\n  IdentitiesOnly yes</pre>",
      "Check it works: <code>ssh %{user}@%{host} true</code> — no output means success.",
      "Then deploy again."
    ]
  }.freeze

  SIGNATURES = [
    SSH_AUTH,
    {
      match: /Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED/i,
      title: "The server's identity isn't recognised",
      explanation:
        "SSH won't connect to a host it hasn't seen before, or one whose key has " \
        "changed since last time. If you've just rebuilt or replaced the server, the " \
        "change is expected. If you haven't, stop and find out why it changed.",
      steps: [
        "Connect once by hand and accept the key: <code>ssh %{user}@%{host}</code>",
        "If the key legitimately changed, remove the old one first: " \
        "<code>ssh-keygen -R %{host}</code>",
        "Then deploy again."
      ]
    },
    {
      match: /Could not resolve hostname|Name or service not known|nodename nor servname/i,
      title: "The server's address couldn't be found",
      explanation:
        "DNS has no answer for this hostname. Either it's misspelled in " \
        "<code>config/deploy.yml</code>, or the domain doesn't point anywhere yet.",
      steps: [
        "Check the host in Settings → Deploy.",
        "Confirm DNS resolves: <code>dig +short %{host}</code>",
        "A new domain can take a few hours to propagate."
      ]
    },
    {
      match: /Connection timed out|Operation timed out|No route to host|Connection refused/i,
      title: "The server didn't answer",
      explanation:
        "The address resolved but nothing accepted the connection. The server may be " \
        "off, still booting, or blocking SSH at its firewall.",
      steps: [
        "Check the server is running in your host's dashboard.",
        "Confirm port 22 is open to your address.",
        "Try <code>ssh %{user}@%{host}</code> by hand — the same error means it isn't Roe."
      ]
    },
    {
      match: /unauthorized: authentication required|denied: requested access|" ?login attempt.*failed|incorrect username or password/i,
      title: "The image registry rejected your login",
      explanation:
        "Kamal pushes the built image to a registry before your server pulls it. The " \
        "username or access token it used was refused — tokens expire, and they're " \
        "usually scoped to specific permissions.",
      steps: [
        "Check the registry username and token in Settings → Deploy.",
        "The token needs write access to push images.",
        "Regenerate it at your registry if it's expired, then deploy again."
      ]
    },
    {
      match: /no space left on device|no space left|disk quota exceeded/i,
      title: "The server has run out of disk space",
      explanation:
        "Old images and build layers accumulate with every deploy and eventually fill " \
        "the disk. This is the most common failure on a long-lived small server.",
      steps: [
        "Free the old layers: <code>ssh %{user}@%{host} 'docker system prune -af'</code>",
        "That removes unused images, not your running site.",
        "Then deploy again."
      ]
    }
  ].freeze

  def self.for(log, error = nil, host: nil, user: nil, key: nil)
    new(log, error, host: host, user: user, key: key).diagnosis
  end

  # The view's entry point: diagnose a failed deploy, with the commands filled
  # in from this site's own deploy config so they can be copied as-is rather
  # than adapted. A missing or unreadable config just falls back to
  # placeholders — the explanation is still worth showing.
  def self.for_status(status)
    return nil if status.blank?

    config = begin
      YAML.load_file(SiteConfig::DEPLOY_FILE) || {}
    rescue StandardError
      {}
    end

    self.for(
      status[:log],
      status[:error],
      host: Array(config.dig("kamal", "servers")).map(&:to_s).reject(&:blank?).first,
      # The remote builder always connects as root (see DeployConfigGenerator).
      user: "root",
      key:  Array(config.dig("kamal", "ssh", "keys")).map(&:to_s).reject(&:blank?).first
    )
  end

  def initialize(log, error = nil, host: nil, user: nil, key: nil)
    @text = [ log, error ].compact.join("\n")
    @host = host.presence || "your-server.com"
    @user = user.presence || "root"
    @key  = key.presence || "~/.ssh/your_deploy_key"
  end

  def diagnosis
    return nil if @text.blank?

    found = SIGNATURES.find { |s| @text.match?(s[:match]) }
    return nil unless found

    Diagnosis.new(
      title: found[:title],
      explanation: fill(found[:explanation]),
      steps: found[:steps].map { |step| fill(step) }
    )
  end

  private

  # `format` would choke on the literal % and {} in shell snippets, so the
  # substitution is plain replacement.
  def fill(text)
    text.gsub("%{host}", @host).gsub("%{user}", @user).gsub("%{key}", @key)
  end
end
