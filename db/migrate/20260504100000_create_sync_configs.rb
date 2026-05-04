class CreateSyncConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_configs do |t|
      t.text :token       # encrypted via ActiveSupport::MessageEncryptor (see model)
      t.string :peer_url  # plain — your blog URL isn't a secret
      t.timestamps
    end
  end
end
