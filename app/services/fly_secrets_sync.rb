# Syncs the local install's encryption material to Fly's secret
# store so multi-Machine Fly deploys share consistent keys across
# Machines. Reads secrets from /site/system/secrets/credentials.yml.enc
# (decrypted locally), checks `fly secrets list` for what's already
# set, and pushes only the missing values via `fly secrets set --stage`
# so they take effect on the next `fly deploy`.
#
# Idempotent by default — secrets already present on Fly are
# silently skipped. Pass force: true to rotate (rare; invalidates
# existing sessions and orphans AR-encrypted column data).
#
# Used by two callers, same behavior in both:
#   - PerformDeployJob (auto on Admin → Deploy when target is "fly")
#   - lib/tasks/fly.rake (manual `bin/rails roe:fly:sync_secrets`)
#
# The Fly CLI picks up the app name from fly.toml in the working
# directory, so callers should be in Rails.root (or pass app: to
# override).
class FlySecretsSync
  # The four env vars Fly Machines need for Roe to boot without
  # touching credentials.yml.enc on disk. SECRET_KEY_BASE is
  # consumed by Rails directly from ENV; the AR_ENCRYPTION_* vars
  # are wired into Active Record encryption config in
  # config/application.rb when FLY_APP_NAME is present.
  ENV_KEYS = {
    secret_key_base:    "SECRET_KEY_BASE",
    primary_key:        "AR_ENCRYPTION_PRIMARY_KEY",
    deterministic_key:  "AR_ENCRYPTION_DETERMINISTIC_KEY",
    key_derivation_salt: "AR_ENCRYPTION_KEY_DERIVATION_SALT"
  }.freeze

  Result = Struct.new(:set_keys, :skipped_keys, keyword_init: true) do
    def any_set?    = set_keys.any?
    def all_skipped? = set_keys.empty? && skipped_keys.any?
  end

  def self.run(app: nil, force: false, logger: Rails.logger)
    new(app: app, force: force, logger: logger).run
  end

  def initialize(app:, force:, logger:)
    @app    = app
    @force  = force
    @logger = logger
  end

  # Returns a Result with the names that were set vs. skipped.
  # Raises with a descriptive message on any unrecoverable failure
  # (missing local secrets, fly auth, fly CLI errors).
  def run
    values   = load_local_secrets
    existing = fetch_fly_secret_names

    to_set  = {}
    skipped = []

    values.each do |env_name, value|
      if existing.include?(env_name) && !@force
        skipped << env_name
      else
        to_set[env_name] = value
      end
    end

    if to_set.empty?
      log "All Fly secrets already set — nothing to sync"
    else
      stage_fly_secrets(to_set)
    end

    Result.new(set_keys: to_set.keys, skipped_keys: skipped)
  end

  private

  def load_local_secrets
    secrets_dir      = RoeSitePaths::SITE_SYSTEM_SECRETS_PATH
    master_key_path  = File.join(secrets_dir, "master.key")
    credentials_path = File.join(secrets_dir, "credentials.yml.enc")

    unless File.exist?(master_key_path) && File.exist?(credentials_path)
      raise "Local secrets missing at #{secrets_dir} — run `bin/setup` to generate master.key + credentials.yml.enc, then retry"
    end

    require "active_support/encrypted_configuration"
    enc_config = ActiveSupport::EncryptedConfiguration.new(
      config_path: credentials_path,
      key_path:    master_key_path,
      env_key:     "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )

    decoded = enc_config.config

    out = {
      ENV_KEYS[:secret_key_base]     => decoded[:secret_key_base].to_s,
      ENV_KEYS[:primary_key]         => decoded.dig(:active_record_encryption, :primary_key).to_s,
      ENV_KEYS[:deterministic_key]   => decoded.dig(:active_record_encryption, :deterministic_key).to_s,
      ENV_KEYS[:key_derivation_salt] => decoded.dig(:active_record_encryption, :key_derivation_salt).to_s
    }

    missing = out.select { |_, v| v.empty? }.keys
    raise "credentials.yml.enc is missing: #{missing.join(', ')} — run `bin/setup` to seed them, then retry" if missing.any?

    out
  end

  def fetch_fly_secret_names
    require "open3"
    out, err, status = Bundler.with_original_env do
      Open3.capture3(*fly_command("secrets", "list"))
    end

    unless status.success?
      if err =~ /auth|login|authoriz|token/i
        raise "Fly authentication isn't set up. Run `fly auth login` from a terminal once, then retry the deploy."
      end
      raise "Could not list Fly secrets: #{(err.presence || out).strip}"
    end

    # `fly secrets list` output:
    #   NAME            DIGEST          CREATED AT
    #   FOO             abc123...       ...
    out.lines.drop(1).map { |l| l.strip.split(/\s+/).first }.compact
  end

  def stage_fly_secrets(secrets)
    log "Staging #{secrets.size} Fly secret#{'s' if secrets.size != 1} (effective on next deploy): #{secrets.keys.join(', ')}"

    args = secrets.map { |k, v| "#{k}=#{v}" }
    out, err, status = Bundler.with_original_env do
      Open3.capture3(*fly_command("secrets", "set", "--stage", *args))
    end

    unless status.success?
      raise "Failed to set Fly secrets: #{(err.presence || out).strip}"
    end
  end

  def fly_command(*args)
    # Always include the app via flag rather than relying on the
    # CWD's fly.toml — makes the call work even when callers
    # haven't chdir'd to Rails.root.
    base = [ "fly", *args ]
    base += [ "--app", @app ] if @app
    base + [ { chdir: Rails.root.to_s } ]
  end

  def log(msg)
    @logger&.info("[FlySecretsSync] #{msg}")
  end
end
