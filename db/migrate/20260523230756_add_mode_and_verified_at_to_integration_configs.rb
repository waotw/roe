class AddModeAndVerifiedAtToIntegrationConfigs < ActiveRecord::Migration[8.1]
  def change
    # Postmark gets mode enum to match Stripe/Snipcart pattern
    add_column :postmark_configs, :mode, :integer, default: 0, null: false

    # All three get verified_at for cached API connection status
    add_column :stripe_configs,   :verified_at, :datetime
    add_column :postmark_configs, :verified_at, :datetime
    add_column :snipcart_configs, :verified_at, :datetime
  end
end
