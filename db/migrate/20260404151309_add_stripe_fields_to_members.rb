class AddStripeFieldsToMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :members, :stripe_customer_id, :string
    add_column :members, :stripe_payment_intent_id, :string
    add_column :members, :paid_at, :datetime

    add_index :members, :stripe_customer_id, unique: true
  end
end
