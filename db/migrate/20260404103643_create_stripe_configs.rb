class CreateStripeConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :stripe_configs do |t|
      # Encrypted keys for test mode
      t.text :publishable_key_test
      t.text :secret_key_test

      # Encrypted keys for live mode
      t.text :publishable_key_live
      t.text :secret_key_live

      # Which mode is active (0 = test, 1 = live)
      t.integer :mode, default: 0, null: false

      # Track when connected
      t.datetime :connected_at

      t.timestamps
    end
  end
end
