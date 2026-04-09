class AddWebhookTokenToPostmarkConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :postmark_configs, :webhook_token, :string
  end
end
