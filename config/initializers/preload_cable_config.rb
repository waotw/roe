# Preload Action Cable's config at boot so the in-app updater can't trip
# over a lazy read of config/cable.yml.
#
# Action Cable reads config/cable.yml LAZILY — the first WebSocket
# connection (Turbo Streams opens one; e.g. the newsletter-status page's
# `turbo_stream_from`) triggers `config_for(:cable)` via Action Cable's
# on_load hook, which then caches the result for the process's life.
#
# That lazy timing is the problem during an update. SwitchManager swaps
# current/ with two renames — current/ → current.backup/, then staging/ →
# current/ — and BETWEEN them current/ briefly does not exist. A cable
# connection (a persistent Turbo Streams socket reconnecting, say) that
# lands in that window resolves the config dir to nil and Rails raises:
#
#     Could not load configuration. No such file - /cable.yml
#
# It clears on the next restart (which reboots from the intact current/),
# but users shouldn't see it at all.
#
# Reading the cable config now — at boot, from the intact current/ —
# caches it before any swap can happen, so no lazy read can hit the
# window. Guarded so a missing or odd cable.yml can never break boot.
Rails.application.config.after_initialize do
  ActionCable.server.config.cable
rescue => e
  Rails.logger.warn "[cable preload] skipped: #{e.class}: #{e.message}"
end
