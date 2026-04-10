class RemovePublishedToFromPosts < ActiveRecord::Migration[8.0]
  def change
    remove_column :posts, :published_to, :integer
  end
end
