class CreateDocumentation < ActiveRecord::Migration[7.1]
  def change
    create_table :documentation do |t|
      t.string :file_path, null: false
      t.text :content
      t.json :metadata, default: {}

      t.timestamps
    end

    add_index :documentation, :file_path, unique: true
  end
end
