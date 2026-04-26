class CreateDisputes < ActiveRecord::Migration[8.1]
  def change
    create_table :disputes do |t|
      t.string :stripe_dispute_id, null: false
      t.string :stripe_charge_id
      t.integer :status, default: 0, null: false   # 0 = open, 1 = closed
      t.integer :amount_cents
      t.string :currency
      t.timestamps
    end

    add_index :disputes, :stripe_dispute_id, unique: true
    add_index :disputes, :status
  end
end
