class ClearLegacyEncryptedIntegrationKeys < ActiveRecord::Migration[8.1]
  # The old homebrew encrypt/decrypt used secret_key_base[0..31] which is
  # not the same as Rails AR Encryption (master.key). Existing values are
  # unreadable under the new scheme, so wipe them cleanly. Re-enter keys
  # in Admin after running this migration.
  def up
    execute "UPDATE stripe_configs SET publishable_key_test = NULL, secret_key_test = NULL, publishable_key_live = NULL, secret_key_live = NULL, webhook_signing_secret_test = NULL, webhook_signing_secret_live = NULL, connected_at = NULL"
    execute "UPDATE postmark_configs SET server_token = NULL, webhook_token = NULL, connected_at = NULL"
    execute "UPDATE snipcart_configs SET api_key_test = NULL, api_key_live = NULL, connected_at = NULL"
  end

  def down
    # Irreversible — old encrypted values are gone
    raise ActiveRecord::IrreversibleMigration
  end
end
