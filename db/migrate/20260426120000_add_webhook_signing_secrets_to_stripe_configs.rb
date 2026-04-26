class AddWebhookSigningSecretsToStripeConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :stripe_configs, :webhook_signing_secret_test, :string
    add_column :stripe_configs, :webhook_signing_secret_live, :string
  end
end
