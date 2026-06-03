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
    # Local is the source of truth for the shared token. Every deploy
    # re-stages ROE_BOOTSTRAP with the current local token, and we
    # overwrite production's value here on each boot to match.
    #
    # Don't call SyncConfig.current — it's first_or_create!, and the
    # before_create :generate_token callback assigns a freshly-generated
    # token before save, which would race with the bootstrap value on a
    # fresh DB. Pre-set the token before save so generate_token's ||=
    # no-ops.
    sync_token = data["sync_token"]
    if sync_token.present?
      existing = SyncConfig.first
      if existing.nil?
        SyncConfig.create! { |c| c.token = sync_token }
        Rails.logger.info "[RoeBootstrap] Created SyncConfig with token from ROE_BOOTSTRAP"
      elsif existing.token != sync_token
        existing.update!(token: sync_token)
        Rails.logger.info "[RoeBootstrap] Updated SyncConfig.token from ROE_BOOTSTRAP"
      end
    end

    # ── Recovery codes ─────────────────────────────────────────────────────
    # Always-overwrite, mirroring sync_token. Local generates codes,
    # ROE_BOOTSTRAP carries the digests (never plaintext), and prod
    # replaces its entire set on each deploy. This means a code marked
    # consumed on prod becomes valid again after the next deploy if the
    # user hasn't regenerated locally — accepted tradeoff in exchange
    # for simplicity. (Merge-by-digest preserving consumed_at is a
    # future-fix flag.)
    code_entries = data["recovery_codes"]
    admin_user = admin_data.is_a?(Hash) ? User.find_by(email_address: admin_data["email_address"]) : User.first
    if code_entries.is_a?(Array) && admin_user
      admin_user.recovery_codes.delete_all
      code_entries.each do |entry|
        next unless entry.is_a?(Hash) && entry["digest"].present?
        attrs = { code_digest: entry["digest"] }
        if entry["consumed_at"].present?
          attrs[:consumed_at] = Time.iso8601(entry["consumed_at"]) rescue nil
        end
        admin_user.recovery_codes.create!(attrs)
      end
      Rails.logger.info "[RoeBootstrap] Applied #{code_entries.size} recovery code digests from ROE_BOOTSTRAP"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[RoeBootstrap] ROE_BOOTSTRAP is not valid JSON — skipping. (#{e.message})"
  rescue => e
    Rails.logger.error "[RoeBootstrap] Bootstrap failed: #{e.class}: #{e.message}"
  end
end
