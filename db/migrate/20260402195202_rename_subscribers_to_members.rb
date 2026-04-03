class RenameSubscribersToMembers < ActiveRecord::Migration[8.0]
  def change
    rename_table :subscribers, :members
  end
end
