class AddNoteToUpdateStatuses < ActiveRecord::Migration[8.1]
  def change
    add_column :update_statuses, :note, :string
  end
end
