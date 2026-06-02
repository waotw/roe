# Roe production bootstrap.
#
# Reads ENV["ROE_BOOTSTRAP"] (set by PerformDeployJob#sync_fly_bootstrap_data
# at deploy time) and seeds the production database with:
#
#   - An initial admin User (so the operator can log in to the production
#     admin UI without SSH).
#   - The Site Sync shared token (so cross-environment sync works
#     immediately after first deploy).
#
# Both operations are guarded by "only if not already present" checks, so
# this initializer is a safe no-op on every redeploy after the first.
# The Fly secret can be left in place or unset manually after first boot:
#
#   fly secrets unset ROE_BOOTSTRAP -a <app-name>
#
# Runs only in production. Skipped in dev/test where the bootstrap
# mechanism isn't applicable.
Rails.application.config.after_initialize do
  next unless Rails.env.production?
  next if ENV["ROE_BOOTSTRAP"].blank?

  begin
    data = JSON.parse(ENV["ROE_BOOTSTRAP"])

    # ── Admin user ─────────────────────────────────────────────────────────
    admin_data = data["admin"]
    if admin_data.is_a?(Hash) && admin_data["email_address"].present?
      if User.exists?
        Rails.logger.info "[RoeBootstrap] Admin user(s) already exist — skipping admin create"
      else
        # Insert directly, preserving the bcrypt password_digest verbatim
        # so the operator's local password works on production without
        # re-entry. Using `insert!` skips has_secure_password's "you
        # must set password" callback that would otherwise complain.
        User.new(email_address: admin_data["email_address"]).tap do |u|
          u.password_digest = admin_data["password_digest"]
          u.save!(validate: false)
        end
        Rails.logger.info "[RoeBootstrap] Created admin user from ROE_BOOTSTRAP"
      end
    end

    # ── Site Sync token ────────────────────────────────────────────────────
    sync_token = data["sync_token"]
    if sync_token.present?
      existing = SyncConfig.current
      if existing.token.present?
        Rails.logger.info "[RoeBootstrap] SyncConfig.token already present — skipping token sync"
      else
        existing.update!(token: sync_token)
        Rails.logger.info "[RoeBootstrap] Set SyncConfig.token from ROE_BOOTSTRAP"
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[RoeBootstrap] ROE_BOOTSTRAP is not valid JSON — skipping. (#{e.message})"
  rescue => e
    Rails.logger.error "[RoeBootstrap] Bootstrap failed: #{e.class}: #{e.message}"
  end
end
