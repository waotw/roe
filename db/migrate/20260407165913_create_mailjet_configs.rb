class CreateMailjetConfigs < ActiveRecord::Migration[8.1]
  def change
    create_table :mailjet_configs do |t|
      t.string :api_key
      t.string :secret_key
      t.datetime :connected_at

      t.timestamps
    end
  end
end
