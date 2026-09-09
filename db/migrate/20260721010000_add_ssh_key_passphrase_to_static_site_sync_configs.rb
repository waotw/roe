class AddSshKeyPassphraseToStaticSiteSyncConfigs < ActiveRecord::Migration[8.1]
  # Passphrase for an encrypted SSH private key. Some hosts (notably cPanel)
  # only ever generate passphrase-protected keys, so SFTP key auth needs a
  # place to store the passphrase. Encrypted at rest via `encrypts` on the
  # model — same treatment as :password and :ssh_private_key.
  def change
    add_column :static_site_sync_configs, :ssh_key_passphrase, :text
  end
end
