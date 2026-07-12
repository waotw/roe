class AddPeerEnvToSyncConfigs < ActiveRecord::Migration[8.1]
  # Plaintext JSON of the peer's environment (folder_name, deploy_target),
  # learned over the sync handshake. Deliberately NOT encrypted: it's used to
  # render restart/recovery instructions, which must be readable even when AR
  # encryption is broken (the exact moment those instructions matter).
  def change
    add_column :sync_configs, :peer_env, :text
  end
end
