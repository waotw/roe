class AddProtocolToStaticSiteSyncConfigs < ActiveRecord::Migration[8.1]
  def change
    # 0 = sftp (default, what existing rows used), 1 = ftps, 2 = zip
    add_column :static_site_sync_configs, :protocol, :integer, default: 0, null: false
  end
end
