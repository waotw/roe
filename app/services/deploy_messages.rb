# frozen_string_literal: true

# Every message a deploy can show — what went wrong and what to do next.
#
# The wording lives in app/views/admin/deploy_messages/, one file per message,
# so it can be edited and styled like any other page. This file only names
# them and gives each a one-line title, because the title is also written
# outside a page: into the deploy log and the short error line, which Ruby
# writes before any view exists.
#
# Deciding *which* message applies is not done here either: DeployPreflight
# picks one before a deploy starts, DeployDiagnostics recognises one in a
# failed deploy's log, and DeployWatchdog notices a deploy Roe lost track of.
module DeployMessages
  TITLES = {
    # Before a deploy, or read off its log
    "docker_not_running"  => "Docker isn't running on this computer",
    "fly_cli_missing"     => "The Fly command-line tool isn't installed",
    "fly_signed_out"      => "You're not signed in to Fly",
    "fly_unreachable"     => "Roe couldn't reach Fly",

    # Read off a failed deploy's log
    "deploy_stalled"      => "The deploy stopped responding",
    "deploy_lock_held"    => "A previous deploy is still holding the lock",
    "server_identity"     => "The server's identity isn't recognised",
    "server_not_found"    => "The server's address couldn't be found",
    "server_no_answer"    => "The server didn't answer",
    "registry_login"      => "The image registry rejected your login",
    "server_disk_full"    => "The server has run out of disk space",

    # When Roe lost track of a deploy (DeployWatchdog)
    "deploy_interrupted"  => "Roe stopped before this deploy finished",

    # Settings → Deploy only
    "kamal_cli_missing"   => "Kamal isn't available",

    # Anything Roe doesn't recognise
    "unrecognised"        => "Roe doesn't recognise this failure"
  }.freeze

  def self.title(key) = TITLES.fetch(key.to_s)

  def self.known?(key) = TITLES.key?(key.to_s)
end
