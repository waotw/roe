module SiteSync
  # Read-only drift check. Walks /site, diffs against the recorded
  # ledger, returns a state hash for the banner and details page.
  #
  # MVP only reports LOCAL drift (this side's filesystem vs this side's
  # ledger). Cross-environment drift detection (does the OTHER side
  # have changes?) is deferred until the exchange/coordination
  # mechanism lands.
  class Checker
    CACHE_KEY = "site_sync:status".freeze
    CACHE_TTL = 30.seconds

    class << self
      # State values:
      #   :clean        filesystem matches the recorded ledger, OR no
      #                 ledger has been written yet (treated as clean
      #                 since there's no baseline to drift from). The
      #                 ledger gets established automatically on the
      #                 next backup or restore — the user shouldn't
      #                 have to think about it.
      #   :local_drift  filesystem differs from the recorded ledger
      #                 (modified/added/deleted files)
      #   :error        couldn't compute (e.g. /site missing)
      def status
        current = SiteSync::Ledger.current
        recorded = SiteSync::Ledger.recorded

        if recorded.nil?
          return {
            state: :clean,
            local: { modified: [], added: [], deleted: [] },
            recorded_at: nil
          }
        end

        diff = SiteSync::Ledger.diff(current, recorded["files"] || {})
        clean = diff[:modified].empty? && diff[:added].empty? && diff[:deleted].empty?

        {
          state: clean ? :clean : :local_drift,
          local: diff,
          recorded_at: recorded["version"]
        }
      rescue => e
        Rails.logger.error "[SiteSync::Checker] status failed: #{e.message}"
        # Fail safe — banner + page get an explicit error state rather
        # than crashing the admin layout.
        { state: :error, error: e.message, local: { modified: [], added: [], deleted: [] }, recorded_at: nil }
      end

      # Cached for the layout banner so admin renders don't re-walk /site
      # on every request. The walk itself is fast but solid_cache + a
      # 30s window means the cost amortizes across page loads.
      def status_cached
        Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { status }
      end

      def clear_cache
        Rails.cache.delete(CACHE_KEY)
      end
    end
  end
end
