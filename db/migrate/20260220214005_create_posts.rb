class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.string :title
      t.string :url_name
      t.date :date
      t.string :author
      t.string :file_path
      t.text :content

      t.timestamps
    end
  end
end
