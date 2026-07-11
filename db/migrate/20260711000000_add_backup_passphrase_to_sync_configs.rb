class AddBackupPassphraseToSyncConfigs < ActiveRecord::Migration[8.1]
  # The passphrase that encrypts the SQLite DB inside full-site backups.
  # AR-encrypted at rest (see SyncConfig#backup_passphrase), so this plain
  # text column only ever holds ciphertext. Nullable — the feature is
  # opt-in and only surfaced when members/store is enabled.
  def change
    add_column :sync_configs, :backup_passphrase, :text
  end
end
