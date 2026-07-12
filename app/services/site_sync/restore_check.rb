require "fileutils"

module SiteSync
  # Post-restore health check for encryption. A database restore is DB-only
  # (we never auto-swap the encryption credentials — that clobbered a live
  # site once). But the restored DB's encrypted columns are only readable with
  # the credentials they were written under. So after a restore we run one
  # self-check: try to read an encrypted value; if it can't be decrypted, flag
  # a "credentials mismatch" so the UI can offer to apply the backup's parked
  # credentials (see SiteSync::PendingRestore).
  #
  # State lives in plaintext marker files next to the DB — never in the DB,
  # never encrypted — so it survives restarts and is readable even when AR
  # encryption is exactly the thing that's broken.
  class RestoreCheck
    MARKER_DIR      = RoeSitePaths::SITE_DB_PATH
    NEEDED_MARKER   = File.join(MARKER_DIR, ".restore-check-needed").freeze
    MISMATCH_MARKER = File.join(MARKER_DIR, ".restore-credentials-mismatch").freeze
    # Set to false to revert. Lives in the secrets dir (where the credentials
    # it applies are) so the boot block finds it. Consumed at boot.
    APPLY_REQUEST_MARKER = File.join(RoeSitePaths::SITE_SYSTEM_SECRETS_PATH, ".apply-backup-credentials").freeze
    # Written by boot when the applied credentials failed to validate + were
    # reverted, so the UI can say "couldn't recover from the backup".
    APPLY_FAILED_MARKER  = File.join(MARKER_DIR, ".restore-credentials-apply-failed").freeze

    # Singleton config models that hold AR-encrypted integration secrets.
    PROBE_MODELS = %w[PostmarkConfig StripeConfig SnipcartConfig StaticSiteSyncConfig].freeze

    class << self
      # Called when a DB restore is applied (boot / apply_if_present!) — the
      # boot block writes the same file inline, since autoloading isn't ready
      # that early. Keep the path in sync.
      def mark_needed!
        FileUtils.mkdir_p(MARKER_DIR)
        File.write(NEEDED_MARKER, Time.now.utc.iso8601)
      end

      def needed?
        File.exist?(NEEDED_MARKER)
      end

      def credentials_mismatch?
        File.exist?(MISMATCH_MARKER)
      end

      # Ask the next boot to install + validate the backup's parked credentials.
      def request_credentials_apply!
        FileUtils.mkdir_p(File.dirname(APPLY_REQUEST_MARKER))
        File.write(APPLY_REQUEST_MARKER, Time.now.utc.iso8601)
      end

      def apply_requested?
        File.exist?(APPLY_REQUEST_MARKER)
      end

      # True when the last apply attempt installed the backup credentials, they
      # failed to validate, and boot reverted to the previous working pair.
      def apply_failed?
        File.exist?(APPLY_FAILED_MARKER)
      end

      def clear_apply_failed!
        FileUtils.rm_f(APPLY_FAILED_MARKER)
      end

      # Run the check at most once per restore (gated by the needed marker).
      # Cheap no-op when no restore is pending. Never raises into the caller.
      def run_if_pending!
        return unless needed?

        begin
          if encrypted_data_readable?
            clear_mismatch!
          else
            flag_mismatch!
          end
        rescue => e
          Rails.logger.warn "[SiteSync::RestoreCheck] probe error: #{e.class} #{e.message}"
        ensure
          FileUtils.rm_f(NEEDED_MARKER)
        end
      end

      # True if every set encrypted value decrypts cleanly (or there's nothing
      # encrypted to read). False if any encrypted column can't be decrypted —
      # missing keys (Configuration) or wrong keys (Decryption).
      def encrypted_data_readable?
        PROBE_MODELS.each do |name|
          klass = name.safe_constantize
          next unless klass.respond_to?(:encrypted_attributes)

          record = klass.respond_to?(:current) ? klass.current : klass.first
          next unless record

          klass.encrypted_attributes.each { |attr| record.public_send(attr) }
        end
        true
      rescue ActiveRecord::Encryption::Errors::Base => e
        Rails.logger.warn "[SiteSync::RestoreCheck] encrypted data unreadable: #{e.class} #{e.message}"
        false
      end

      def flag_mismatch!
        FileUtils.mkdir_p(MARKER_DIR)
        File.write(MISMATCH_MARKER, Time.now.utc.iso8601)
      end

      def clear_mismatch!
        FileUtils.rm_f(MISMATCH_MARKER)
      end

      # Clear all restore-check state (e.g. after credentials are successfully
      # applied, or the admin dismisses it).
      def clear!
        [ NEEDED_MARKER, MISMATCH_MARKER, APPLY_REQUEST_MARKER, APPLY_FAILED_MARKER ].each { |f| FileUtils.rm_f(f) }
      end
    end
  end
end
