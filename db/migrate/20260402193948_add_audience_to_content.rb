class AddAudienceToContent < ActiveRecord::Migration[8.0]
  def change
    # Add audience column to all content types
    add_column :posts, :audience, :string, default: "everyone", null: false
    add_column :pages, :audience, :string, default: "everyone", null: false
    add_column :documentation, :audience, :string, default: "everyone", null: false

    # Add indexes for filtering
    add_index :posts, :audience
    add_index :pages, :audience
    add_index :documentation, :audience
  end
end
