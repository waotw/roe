class AddSshKeyPathToSyncConfigs < ActiveRecord::Migration[8.1]
  def change
    # Absolute path to a private key the user has selected for Site
    # Sync's rsync calls. Not encrypted — paths aren't secret. The
    # key file itself stays under ~/.ssh where the OS keychain /
    # ssh-agent protect it.
    add_column :sync_configs, :ssh_key_path, :string
  end
end
