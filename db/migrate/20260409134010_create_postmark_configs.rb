class CreatePostmarkConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :postmark_configs do |t|
      t.text :server_token  # Encrypted
      t.datetime :connected_at

      t.timestamps
    end
  end
end
