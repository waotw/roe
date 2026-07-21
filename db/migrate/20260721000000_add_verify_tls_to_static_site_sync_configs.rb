class AddVerifyTlsToStaticSiteSyncConfigs < ActiveRecord::Migration[8.1]
  # FTPS to shared / cPanel hosts frequently presents a self-signed or
  # hostname-mismatched TLS certificate. With verify_tls false, the FTPS
  # pusher keeps the channel encrypted but skips certificate verification —
  # the familiar "trust this certificate" escape hatch. Defaults to true.
  def change
    add_column :static_site_sync_configs, :verify_tls, :boolean, default: true, null: false
  end
end
