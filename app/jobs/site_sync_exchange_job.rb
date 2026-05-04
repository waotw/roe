class SiteSyncExchangeJob < ApplicationJob
  queue_as :default

  # Pings the peer for its current state and stores the response.
  # Scheduled hourly via config/recurring.yml on the dev side, and
  # also enqueued opportunistically by SiteSync::Exchange.refresh_if_stale
  # whenever the cached peer state is older than 60 seconds.
  #
  # No-op when this side isn't configured to call out (production,
  # or any env without peer_url + token in credentials).
  def perform
    SiteSync::Exchange.call_peer
  end
end
