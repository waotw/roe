class CreateSubscribers < ActiveRecord::Migration[8.0]
  def change
    create_table :subscribers do |t|  # ← Regular integer ID
      # Identity
      t.string :email, null: false
      t.string :name

      # Membership tier (enum: free=0, paid=1)
      t.integer :tier, default: 0, null: false

      # Status (enum: active=0, cancelled=1)
      t.integer :status, default: 0, null: false

      # Authentication (only for paid tier)
      t.string :password_digest

      # Access token for Cloudflare Workers ("UUID")
      t.string :access_token, null: false, limit: 36

      # Timestamps
      t.datetime :subscribed_at
      t.datetime :cancelled_at

      # Metadata (Stripe customer_id, subscription_id, etc.)
      t.json :metadata, default: {}

      t.timestamps

      # Indexes
      t.index :email, unique: true
      t.index :access_token, unique: true
      t.index [:tier, :status]
      t.index :status
    end
  end
end
