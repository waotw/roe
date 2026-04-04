class AddCurrencyToStripeConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :stripe_configs, :currency, :string
    add_column :stripe_configs, :product_id, :string
    add_column :stripe_configs, :price_id, :string
  end
end
