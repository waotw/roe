# Snipcart order history. Roe receives order webhooks from Snipcart (which has
# no management/read API) and stores each completed order so the admin can see
# shop activity — and, crucially, link a buyer to a Roe member by email, which
# Snipcart itself can't do.
#
# The raw Snipcart payload is kept in `payload` so later features (line items,
# subscriptions, addresses) can read fields we don't model yet without a
# re-import. `snipcart_token` is Snipcart's own order token, unique, so webhook
# retries upsert rather than duplicate.
class CreateSnipcartOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :snipcart_orders do |t|
      t.string  :snipcart_token, null: false
      t.string  :email
      t.string  :name
      t.integer :total_cents
      t.string  :currency
      t.string  :status
      t.integer :refunded_amount_cents
      t.string  :refunded_currency
      t.datetime :refunded_at
      t.datetime :placed_at
      t.json    :payload, default: {}, null: false
      t.timestamps
    end

    add_index :snipcart_orders, :snipcart_token, unique: true
    add_index :snipcart_orders, :email
    add_index :snipcart_orders, :placed_at
  end
end
