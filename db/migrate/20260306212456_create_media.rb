class CreateMedia < ActiveRecord::Migration[8.1]
  def change
    create_table :media do |t|
      t.string :file_path
      t.string :media_type
      t.datetime :uploaded_at

      t.timestamps
    end
    add_index :media, :file_path, unique: true
  end
end
