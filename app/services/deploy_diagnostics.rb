# frozen_string_literal: true

# Reads a failed deploy's log and says, in plain terms, what went wrong.
#
# Kamal and Docker report failures in their own vocabulary — `docker system
# dial-stdio has exited with exit status 255` names the mechanism that failed,
# not the thing you have to go and fix. Someone deploying their own site once a
# month has no way to translate that.
#
# So: match the handful of failures that actually recur, and name the message
# that says what happened and what to do — the wording is in
# app/views/admin/deploy_messages/, one file per message. A failure that
# matches nothing gets the "unrecognised" message, and the raw log below it.
class DeployDiagnostics
  # `key` names the message — its wording is in
  # app/views/admin/deploy_messages/_<key>.html.erb and its title in
  # DeployMessages. `locals` are this site's deploy details, which the message
  # puts into commands so they can be copied as they are.
  Diagnosis = Struct.new(:key, :locals, keyword_init: true) do
    def title = DeployMessages.title(key)
  end

  # How each recognisable failure shows up in a log. Only the patterns live
  # here; what to say about each is the message file named by `key`.
  #
  # Ordered most specific first; the first match wins. A pattern that could
  # match another's log has to come before it.
  SIGNATURES = [
    # First, and matched on a marker Roe writes rather than on command output:
    # a stall is defined by the command printing nothing, so there is no log
    # text to recognise.
    { key: "deploy_stalled", match: /roe: deploy stalled/ },

    # Kamal holds a deploy lock on the primary host for the length of a deploy
    # and releases it at the end. A deploy that was interrupted never gets to,
    # so the *next* deploy fails here — it reads as a new problem when it's
    # the residue of an old one, which is why it's near the top: the lock
    # message can accompany almost anything. Both strings are Kamal's own
    # (Kamal::Cli::Base#raise_if_locked).
    { key: "deploy_lock_held", match: /Deploy lock already in place|Deploy lock found/i },

    # `docker system dial-stdio` is Docker reaching for the *remote* builder.
    # It only gets there because the local Docker daemon wasn't available to
    # build with — so the useful answer is "start Docker", not "fix your SSH".
    # Kamal's own connection to the server goes through net-ssh with the key
    # in deploy.yml and is working fine if the deploy got this far.
    { key: "docker_not_running",
      match: /Cannot connect to the Docker daemon|Is the docker daemon running|docker daemon is not running|dial-stdio.*exit status 255|error during connect.*docker_engine/mi },

    # A Fly login that dies at the network level reports an error too, and
    # answering it with "sign in again" sends someone to a command that fails
    # the same way — so unreachable comes before signed out.
    { key: "fly_unreachable",
      match: %r{api\.fly\.io.*?: EOF|Post "https://api\.fly\.io[^"]*": (EOF|.*timeout)|dial tcp.*fly\.io}i },

    # Fly's own wording only. A generic /authenticat/ would also match the
    # registry failure further down ("unauthorized: authentication required")
    # and answer a Kamal problem with "run fly auth login". DeployPreflight
    # catches this before a deploy; this is for a session that ends mid-deploy.
    { key: "fly_signed_out",
      match: /You must be authenticated to view this|failed retrieving current user|fly auth login/i },

    { key: "server_identity",  match: /Host key verification failed|REMOTE HOST IDENTIFICATION HAS CHANGED/i },
    { key: "server_not_found", match: /Could not resolve hostname|Name or service not known|nodename nor servname/i },
    { key: "server_no_answer", match: /Connection timed out|Operation timed out|No route to host|Connection refused/i },
    { key: "registry_login",
      match: /unauthorized: authentication required|denied: requested access|" ?login attempt.*failed|incorrect username or password/i },
    { key: "server_disk_full", match: /no space left on device|no space left|disk quota exceeded/i }
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

  def self.for(log, error = nil, host: nil, user: nil, key: nil, target: nil)
    new(log, error, host: host, user: user, key: key, target: target).diagnosis
  end

  # The view's entry point for a log: diagnose a failed deploy, with this
  # site's own deploy details so its commands can be copied as they are. A
  # missing or unreadable config falls back to placeholders — the message is
  # still worth showing.
  def self.for_status(status)
    return nil if status.blank?

    config = begin
      SiteFile.read_yaml(SiteConfig::DEPLOY_FILE) || {}
    rescue StandardError
      {}
    end

    self.for(
      status[:log],
      status[:error],
      host:   Array(config.dig("kamal", "servers")).map(&:to_s).reject(&:blank?).first,
      # The remote builder always connects as root (see DeployConfigGenerator).
      user:   "root",
      key:    Array(config.dig("kamal", "ssh", "keys")).map(&:to_s).reject(&:blank?).first,
      target: status[:target]
    )
  end

  # Every message a failed deploy shows, in order, each as
  # { key:, context:, locals: } for admin/deploy_messages/_message.
  #
  #   stopped before it started → the checks that stopped it (DeployPreflight)
  #   Roe lost track of it      → deploy_interrupted (DeployWatchdog)
  #   the log names a failure   → that failure's message
  #   anything else             → unrecognised, so there's always a next step
  #
  # A preflight entry saved before messages had names has no key; it's left
  # out here and the page shows its saved wording instead.
  def self.messages_for(status)
    return [] unless status.is_a?(Hash) && status[:state] == :failed

    target = status[:target].to_s.presence

    if (preflight = Array(status[:preflight])).any?
      return preflight.filter_map do |issue|
        key = issue[:key].to_s
        { key: key, context: :before, locals: { target: target } } if DeployMessages.known?(key)
      end
    end

    return [ { key: "deploy_interrupted", context: :during, locals: { target: target } } ] if status[:abandoned]

    if (diagnosis = for_status(status))
      [ { key: diagnosis.key, context: :during, locals: diagnosis.locals } ]
    else
      [ { key: "unrecognised", context: :during, locals: { target: target } } ]
    end
  end

  def initialize(log, error = nil, host: nil, user: nil, key: nil, target: nil)
    @text   = [ log, error ].compact.join("\n")
    @locals = { host: host, user: user, ssh_key: key, target: target.to_s.presence }.compact
  end

  def diagnosis
    return nil if @text.blank?

    found = SIGNATURES.find { |s| @text.match?(s[:match]) }
    return nil unless found

    Diagnosis.new(key: found[:key], locals: @locals)
  end
end
