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

  # `docker system dial-stdio` is Docker reaching for the *remote* builder. It
  # only gets there because the local Docker daemon wasn't available to build
  # with — so the useful answer is "start Docker", not "fix your SSH".
  #
  # Kamal's own connection to the server is unrelated: it goes through net-ssh
  # with the key named in deploy.yml, needs no agent, and is working fine if the
  # deploy got this far. Sending someone to edit ~/.ssh/config here would have
  # them fixing a path they don't use and may never have set up.
  #
  # DeployPreflight raises this same message when it catches the problem before
  # a deploy starts, and reads it from here rather than keeping its own copy —
  # every message a deploy can produce is edited in this file, once.
  DOCKER_DOWN = {
    match: /Cannot connect to the Docker daemon|Is the docker daemon running|docker daemon is not running|dial-stdio.*exit status 255|error during connect.*docker_engine/mi,
    title: "Docker isn't running on this computer",
    explanation:
    "Roe builds your site's image with Docker before sending it to your server. " \
    "Docker has to be running here for a deploy to work.",
    steps: [
      "Open Docker Desktop and wait for it to load.",
      "Then deploy again."
    ]
  }.freeze

  SIGNATURES = [
    # First, and matched on a marker Roe writes rather than on command output:
    # a stall is defined by the command printing nothing, so there is no log
    # text to recognise. Everything below reads what the failure said; this one
    # reads the fact that it said nothing.
    {
      match: /roe: deploy stalled/,
      title: "The deploy stopped responding",
      explanation:
        "The deploy command produced no output for several minutes, so Roe stopped it and " \
        "freed the job. The log above is everything it managed to print before going quiet — " \
        "usually the last thing it did is the thing it got stuck on. A stall like this is " \
        "typically a command waiting on something that will never answer: a prompt nobody can " \
        "see, a connection with no timeout of its own, or a builder that went away mid-build.",
      steps: [
        "Deploy again — a stall is often momentary, such as a slow registry or a builder that dropped.",
        "If it stops at the same point every time, run the deploy command yourself in a terminal — a prompt Roe can't show you will be visible there.",
        "Check for anything waiting on input: an unknown SSH host key or an expired login will wait forever rather than fail.",
        "Nothing was left running — Roe stops the whole process group, so it's safe to deploy again."
      ]
    },
    # Kamal holds a deploy lock on the primary host for the length of a deploy
    # and releases it at the end. A deploy that was interrupted — stalled and
    # stopped, or killed with Roe — never gets to release it, so the *next*
    # deploy fails here. It reads as a new problem when it's the residue of an
    # old one, which is why it's near the top: the lock message can accompany
    # almost anything.
    #
    # Both strings are kamal's own (Kamal::Cli::Base#raise_if_locked): it says
    # "Deploy lock already in place!" and raises "Deploy lock found. ...".
    {
      match: /Deploy lock already in place|Deploy lock found/i,
      title: "A previous deploy is still holding the lock",
      explanation:
        "Kamal takes a lock on the server while it deploys and releases it when it finishes. " \
        "A deploy that was interrupted — stopped for going quiet, or ended when Roe quit — " \
        "never released it, so this deploy can't start. Nothing is wrong with the server or " \
        "with this deploy; the lock is left over.",
      steps: [
        "Check who holds it: <code>kamal lock status</code>.",
        "Release it: <code>kamal lock release</code>.",
        "Deploy again — it will pick up from wherever the interrupted one got to.",
        "If you didn't interrupt anything, make sure a deploy isn't running somewhere else before releasing."
      ]
    },
    DOCKER_DOWN,
    # Fly's own wording when the session is gone. DeployPreflight catches this
    # before a deploy starts, so this is the safety net for a session that
    # expires mid-deploy — or for a log from before the preflight existed.
    # Before the signed-out signature: a login that dies at the network level
    # reports an error too, and answering it with "sign in again" sends someone
    # to a command that fails the same way.
    {
      match: %r{api\.fly\.io.*?: EOF|Post "https://api\.fly\.io[^"]*": (EOF|.*timeout)|dial tcp.*fly\.io}i,
      title: "Roe couldn't reach Fly",
      explanation:
        "The <code>fly</code> command couldn't get an answer from Fly's API. This isn't an " \
        "account problem — signing in again uses the same connection and fails the same way.",
      steps: [
        "Try again in a minute — this is often momentary.",
        "Check status.fly.io for an outage.",
        "If you're on a VPN or a work network, try without it.",
        "Confirm directly: <code>fly auth whoami</code>. The same error means it isn't Roe."
      ]
    },
    {
      # Fly's own wording only. A generic /authenticat/ would also match the
      # registry failure further down ("unauthorized: authentication required")
      # and, sitting above it, would answer a Kamal problem with "run fly auth
      # login".
      match: /You must be authenticated to view this|failed retrieving current user|fly auth login/i,
      title: "Your Fly session has expired",
      explanation:
        "Fly signed you out, so the deploy had no permission to run. A deploy started " \
        "without a session doesn't fail — it hangs with no output — which is why Roe now " \
        "checks before starting.",
      steps: [
        "Open a terminal — any folder will do.",
        "Run <code>fly auth login</code>. It opens your browser.",
        "Sign in to Fly, then return to the terminal.",
        "Then deploy again."
      ]
    },
    {
      match: /Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED/i,
      title: "The server's identity isn't recognised",
      explanation:
        "SSH won't connect to a host it doesn't recognize, or one whose key has " \
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

  # Failures where a stale or corrupt build cache is a plausible culprit.
  #
  # Kept separate from SIGNATURES because this answers a different question.
  # SIGNATURES asks "what went wrong"; this asks "is it worth spending several
  # minutes on a cold build". A failure can be diagnosed and still not be a
  # cache problem — Docker being off is the clearest example.
  CACHE_TROUBLE = /
    failed\ to\ compute\ cache\ key
    |error\ importing\ cache
    |failed\ to\ (solve|export|copy)
    |cache\ (import|export)\ failed
    |content\ digest\ sha256:[a-f0-9]+\ not\ found
    |layer\ does\ not\ exist
    |unexpected\ EOF
    |invalid\ tar\ header
    |manifest\ unknown
  /xi

  # Whether to offer a cold build, and lead with it.
  #
  # Two signals, either sufficient:
  #
  #   the log names something cache-shaped — the reliable case, but our
  #   pattern list will never be complete; and
  #
  #   the deploy has now failed twice — which covers everything the list
  #   misses. One failure is usually something you go and fix (start Docker,
  #   add the token). A second identical trip through means the cheap fix
  #   isn't working, and that's when a cold build stops being a waste.
  #
  # The count matters as much as the patterns. Without it, an unrecognised
  # cache failure would leave someone retrying a warm build forever with no
  # way out offered.
  REPEATED_FAILURES = 2

  def self.cache_suspect?(status)
    return false if status.blank?

    text = [ status[:log], status[:error] ].compact.join("\n")
    return true if text.match?(CACHE_TROUBLE)

    # The count is a fallback for failures we can't read, not an override of
    # ones we can. Docker being off and failing twice is still Docker being
    # off — offering a cold build there sends someone away for several minutes
    # to fix something that was never the problem.
    return false if self.for(text).present?

    status[:consecutive_failures].to_i >= REPEATED_FAILURES
  end

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
