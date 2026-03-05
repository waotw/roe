class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.string :file_path
      t.text :content
      t.json :metadata

      t.timestamps
    end
  end
end
