class CreateMediaReferences < ActiveRecord::Migration[8.1]
  def change
    create_table :media_references do |t|
      t.references :post, null: false, foreign_key: true
      t.references :medium, null: false, foreign_key: true
      t.timestamps
    end

    add_index :media_references, [:post_id, :medium_id], unique: true
    # Removed: add_index :media_references, :medium_id (redundant)
  end
end
