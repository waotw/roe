module PostmarkSetupHelper
  # Whether "Have Roe set up your Postmark integration" is offered, and in which
  # shape. Path A: production runs the full setup (creates + stores the live
  # server token, verifies the webhook end-to-end); local runs the sandbox-only
  # setup (creates the sandbox, seeds its token, discards the account token).
  # Local is deliberately ungated — it touches only the sandbox and sends
  # nothing anywhere, so it needs no deployed site.
  def postmark_setup_mode
    Rails.env.production? ? :live : :sandbox
  end

  # Path B ("send live keys from local") gate, wired now so the UI can grow into
  # it: a live site we've actually heard from recently. Mirrors Site Sync's own
  # reachability signal rather than merely "a peer URL is configured", so we
  # don't offer to send keys to a site that isn't answering.
  def live_site_deployed?
    SiteSync::Exchange.can_call_peer? && SiteSync::Exchange.peer_reachable?
  rescue StandardError
    false
  end

  # Whether local webhook delivery can even be tested — Postmark can't POST to
  # localhost, so it needs a public tunnel host (dev_host / a public
  # allowed_hosts entry). Drives the "set a tunnel to test webhooks locally"
  # hint. Always true in production (the live domain is reachable).
  def postmark_local_webhooks_testable?
    Rails.env.production? || webhook_url("/webhooks/postmark/probe").present?
  end
end
