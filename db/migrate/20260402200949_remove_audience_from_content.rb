class RemoveAudienceFromContent < ActiveRecord::Migration[8.0]
  def change
    remove_column :posts, :audience, :string
    remove_column :pages, :audience, :string
    remove_column :documentation, :audience, :string
  end
end
