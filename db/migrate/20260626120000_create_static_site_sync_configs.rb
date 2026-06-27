class CreateStaticSiteSyncConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :static_site_sync_configs do |t|
      t.string  :host
      t.integer :port, default: 22
      t.string  :username
      t.integer :auth_mode, default: 0
      t.text    :password
      t.text    :ssh_private_key
      t.string  :remote_path

      t.datetime :last_pushed_at
      t.datetime :last_verified_at
      t.string   :last_verification_error

      t.timestamps
    end
  end
end
