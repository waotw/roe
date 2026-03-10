class CreateSiteConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :site_configs do |t|
      t.string :file_path, null: false
      t.json :config, default: {}

      t.timestamps
    end

    add_index :site_configs, :file_path, unique: true
  end
end
