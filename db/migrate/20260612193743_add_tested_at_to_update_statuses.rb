class AddTestedAtToUpdateStatuses < ActiveRecord::Migration[8.1]
  def change
    add_column :update_statuses, :tested_at, :datetime
  end
end
