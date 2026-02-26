class ConvertPostsToJsonMetadata < ActiveRecord::Migration[8.1]
  def change
    # Add the new JSON column
    add_column :posts, :metadata, :json, default: {}

    # Copy existing data into metadata (reversible for rollback)
    reversible do |dir|
      dir.up do
        Post.find_each do |post|
          post.update_column(:metadata, {
            "title" => post.title,
            "url_name" => post.url_name,
            "date" => post.date&.to_s,
            "author" => post.author
          })
        end
      end
    end

    # Remove old columns
    remove_column :posts, :title, :string
    remove_column :posts, :url_name, :string
    remove_column :posts, :date, :date
    remove_column :posts, :author, :string
  end
end
