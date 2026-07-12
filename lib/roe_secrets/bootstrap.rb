require "active_support"
require "active_support/encrypted_configuration"
require "securerandom"
require "yaml"
require "fileutils"

module RoeSecrets
  # Boot-time bootstrap + self-heal of an install's per-install secrets
  # (master.key + credentials.yml.enc), run before Rails reads them. Extracted
  # from config/application.rb so its safety guard is regression-tested — this
  # code destroyed a live site's AR encryption keys once (see the guard below),
  # and boot-critical code that can lose keys must not live untested inline.
  #
  # Handles, idempotently:
  #   1. Fresh install (no master.key / credentials) — generate both, seeding
  #      secret_key_base + active_record_encryption keys.
  #   2. Upgrade-in-place (credentials readable, missing secret_key_base) — add
  #      just secret_key_base; never touch existing AR keys.
  #   3. Steady state — no writes.
  #
  # Never regenerates an existing master.key or secret_key_base (both are
  # write-once: regenerating would brick already-encrypted DB columns / every
  # session cookie).
  module Bootstrap
    module_function

    # Bootstrap secrets under secrets_dir. roe_root / site_path only affect the
    # human-readable warnings. Returns a symbol for tests/telemetry:
    #   :unreadable — credentials present but undecryptable; NOTHING changed
    #   :seeded     — generated master.key and/or added missing credential fields
    #   :noop       — everything already present and readable
    def run!(secrets_dir:, roe_root: nil, site_path: nil)
      master_key_path  = File.join(secrets_dir, "master.key")
      credentials_path = File.join(secrets_dir, "credentials.yml.enc")

      unless File.directory?(secrets_dir)
        FileUtils.mkdir_p(secrets_dir)
        File.chmod(0o700, secrets_dir)
      end

      master_key_was_generated = false
      unless File.exist?(master_key_path)
        File.write(master_key_path, SecureRandom.hex(16))
        File.chmod(0o600, master_key_path)
        master_key_was_generated = true
      end

      enc_config = ActiveSupport::EncryptedConfiguration.new(
        config_path: credentials_path,
        key_path:    master_key_path,
        env_key:     "RAILS_MASTER_KEY",
        raise_if_missing_key: false
      )

      credentials_present = File.exist?(credentials_path) && File.size(credentials_path).to_i.positive?
      raw =
        begin
          enc_config.read
        rescue StandardError
          ""
        end

      # ── THE GUARD ──────────────────────────────────────────────────────
      # A present, NON-EMPTY credentials file that we cannot decrypt (read
      # comes back blank — wrong/empty master.key, RAILS_MASTER_KEY mismatch,
      # corruption) must NEVER be overwritten. Doing so would replace the real
      # (unreadable) active_record_encryption keys with a bare secret_key_base
      # and permanently destroy them. Bail loudly, change nothing; the boot
      # then fails on its own with the real key error — the correct, fully
      # recoverable escalation (fix the key, and the credentials are intact).
      if credentials_present && raw.blank?
        warn "[RoeSecrets] credentials.yml.enc is present but could NOT be decrypted with the " \
             "current key. Refusing to overwrite it — that would destroy your encryption keys. " \
             "Check RAILS_MASTER_KEY / #{master_key_path}. No secrets were changed."
        return :unreadable
      end

      existing = raw.blank? ? {} : (enc_config.config rescue {})
      hash     = raw.blank? ? {} : (YAML.safe_load(raw) || {})
      seeded   = []

      if existing[:secret_key_base].to_s.empty?
        hash["secret_key_base"] = SecureRandom.hex(64)
        seeded << "secret_key_base"
      end

      # Seed AR encryption keys ONLY when we generated master.key in the same
      # run. Anything else (existing master.key, or a credentials file that's
      # simply missing AR keys) means the operator manages them separately —
      # don't overwrite that decision.
      if master_key_was_generated && existing.dig(:active_record_encryption, :primary_key).blank?
        hash["active_record_encryption"] = {
          "primary_key"         => SecureRandom.alphanumeric(32),
          "deterministic_key"   => SecureRandom.alphanumeric(32),
          "key_derivation_salt" => SecureRandom.alphanumeric(32)
        }
        seeded << "active_record_encryption"
      end

      return :noop if seeded.empty?

      enc_config.write(hash.to_yaml)
      File.chmod(0o600, credentials_path)

      rel_key  = roe_root ? master_key_path.sub(roe_root + "/", "") : master_key_path
      rel_cred = roe_root ? credentials_path.sub(roe_root + "/", "") : credentials_path
      parts    = []
      parts << "Generated fresh master.key (#{rel_key})" if master_key_was_generated
      parts << "#{credentials_present ? 'Updated' : 'Created'} #{rel_cred}: #{seeded.join(', ')}"
      warn "[RoeSecrets] #{parts.join(' • ')}"

      if master_key_was_generated
        warn "[RoeSecrets] First-install secrets generated. If this message appears on EVERY boot, " \
             "your persistent volume isn't mounted at #{site_path} — fix that before any encrypted " \
             "data is written, or it'll be unrecoverable across container restarts."
      end

      :seeded
    end
  end
end
