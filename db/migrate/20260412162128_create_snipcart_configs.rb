class CreateSnipcartConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :snipcart_configs do |t|
      # Encrypted API keys for test mode
      t.text :api_key_test

      # Encrypted API keys for live mode
      t.text :api_key_live

      # Which mode is active (0 = test, 1 = live)
      t.integer :mode, default: 0, null: false

      # Track when connected
      t.datetime :connected_at

      t.timestamps
    end
  end
end
