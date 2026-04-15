class AddSourceUrlToMedia < ActiveRecord::Migration[8.1]
  def change
    add_column :media, :source_url, :string
    add_index :media, :source_url

    add_reference :media, :import, foreign_key: true, null: true
  end
end
