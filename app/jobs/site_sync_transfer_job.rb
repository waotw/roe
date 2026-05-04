# Performs a full local↔live transfer in the background. One job
# class handles both directions — they only differ in (a) which side
# gets backed up first and (b) which way the rsync goes.
#
# Status is tracked in a single cache key (only one transfer can run
# at a time anyway) so the admin UI can show in-progress / completed
# / failed without a dedicated table. After a successful transfer
# we also kick off a SiteSyncExchangeJob so the peer's cached view
# of us refreshes immediately rather than waiting for the next
# hourly tick.
class SiteSyncTransferJob < ApplicationJob
  queue_as :default

  STATUS_CACHE_KEY = "site_sync:transfer_status".freeze
  STATUS_TTL       = 1.day

  def perform(kind)
    kind = kind.to_sym
    raise ArgumentError, "kind must be :push or :pull" unless [ :push, :pull ].include?(kind)

    started_at = Time.current
    write_status(state: :running, kind: kind, started_at: started_at)

    case kind
    when :push
      # Snapshot live first so the push is reversible from the
      # local backup list (under site_backups/production/).
      SiteSync::FlyRsync.backup_live_to_local!
      SiteSync::FlyRsync.push_local_to_live!
    when :pull
      # Snapshot local first so the pull is reversible from the
      # local backup list (under site_backups/local/).
      SiteSync::BackupManager.create
      SiteSync::FlyRsync.pull_live_to_local!
    end

    # /site is now in a known-good state matching the other side.
    # Refresh our ledger + caches so drift indicators clear.
    SiteSync::Ledger.write_current!
    SiteSync::Checker.clear_cache
    Rails.cache.delete("site_sync:current_fingerprint")

    # For push: also tell the peer to refresh its ledger. Without
    # this, the peer's drift detection thinks "everything changed"
    # because rsync touched mtimes on every transferred file but
    # the peer's ledger still has the pre-push mtimes. Pull doesn't
    # need this — peer's /site didn't change.
    if kind == :push
      SiteSync::Exchange.refresh_peer_ledger!
    end

    write_status(
      state:        :completed,
      kind:         kind,
      started_at:   started_at,
      completed_at: Time.current
    )

    # Tell the peer about our new state right away — without this,
    # the banner on the other side stays stale until the next
    # hourly exchange run.
    SiteSyncExchangeJob.perform_later if SiteSync::Exchange.can_call_peer?
  rescue => e
    Rails.logger.error "[SiteSyncTransferJob #{kind}] #{e.class}: #{e.message}"
    write_status(
      state:        :failed,
      kind:         kind,
      started_at:   started_at,
      completed_at: Time.current,
      error:        e.message
    )
    raise # let Solid Queue see the failure
  end

  private

  def write_status(data)
    Rails.cache.write(STATUS_CACHE_KEY, data, expires_in: STATUS_TTL)
  end
end
