class CreateDonations < ActiveRecord::Migration[8.1]
  def change
    create_table :donations do |t|
      t.integer :amount_cents, null: false
      t.string :currency, null: false
      t.string :email, null: false
      t.string :stripe_session_id
      t.string :stripe_payment_intent_id
      t.references :member, foreign_key: true, null: true
      t.timestamps
    end

    add_index :donations, :stripe_session_id, unique: true
    add_index :donations, :email
    add_index :donations, :created_at
  end
end
