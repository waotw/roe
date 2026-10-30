# Stripe product/price IDs are mode-specific: an ID created with a test key does
# not exist for a live key (and vice-versa). They were stored in single columns
# (product_id/price_id) while the keys are per-mode, so switching to live mode
# sent test-mode IDs with the live key — "No such price … a similar object
# exists in test mode". Split them per mode to match the keys.
#
# Backfill: the existing single value is copied into the TEST slot. That's the
# safe assumption (a store set up in test mode holds test IDs); a live store just
# re-saves its price once in live mode to populate the live slot.
class SplitStripeProductPriceIdsByMode < ActiveRecord::Migration[8.1]
  def up
    add_column :stripe_configs, :product_id_test, :string
    add_column :stripe_configs, :product_id_live, :string
    add_column :stripe_configs, :price_id_test,   :string
    add_column :stripe_configs, :price_id_live,   :string

    # Existing IDs are assumed test-mode (the common setup path).
    execute <<~SQL.squish
      UPDATE stripe_configs
      SET product_id_test = product_id,
          price_id_test   = price_id
    SQL

    remove_column :stripe_configs, :product_id
    remove_column :stripe_configs, :price_id
  end

  def down
    add_column :stripe_configs, :product_id, :string
    add_column :stripe_configs, :price_id,   :string

    execute <<~SQL.squish
      UPDATE stripe_configs
      SET product_id = product_id_test,
          price_id   = price_id_test
    SQL

    remove_column :stripe_configs, :product_id_test
    remove_column :stripe_configs, :product_id_live
    remove_column :stripe_configs, :price_id_test
    remove_column :stripe_configs, :price_id_live
  end
end
