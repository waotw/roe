class CreateDeploySecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :deploy_secrets do |t|
      t.text :registry_password
      t.timestamps
    end
  end
end
