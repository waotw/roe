class CreateUpdateStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :update_statuses do |t|
      t.string :status, null: false, default: 'pending'
      t.string :from_version
      t.string :to_version
      t.string :current_step
      t.integer :progress_percent, default: 0
      t.text :error_message
      t.text :log
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :update_statuses, :status
    add_index :update_statuses, :created_at
  end
end
