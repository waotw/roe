class RemoveTestColumnsFromUpdateStatuses < ActiveRecord::Migration[8.1]
  def change
    remove_column :update_statuses, :note, :string
    remove_column :update_statuses, :tested_at, :datetime
  end
end
