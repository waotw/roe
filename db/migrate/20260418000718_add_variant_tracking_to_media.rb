class AddVariantTrackingToMedia < ActiveRecord::Migration[8.1]
  def change
    add_column :media, :variants_status, :string, default: "pending"
    add_column :media, :variants_generated_at, :datetime
    add_index :media, :variants_status
  end
end
