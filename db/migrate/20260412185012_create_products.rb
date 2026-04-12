class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.text :content
      t.string :file_path
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :products, :file_path, unique: true
  end
end
