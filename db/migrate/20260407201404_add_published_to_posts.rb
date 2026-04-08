class AddPublishedToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :published_to, :integer, default: 0, null: false

    # Set existing posts to 'site' (value: 0) to maintain current behavior
    reversible do |dir|
      dir.up do
        Post.update_all(published_to: 0)
      end
    end
  end
end
