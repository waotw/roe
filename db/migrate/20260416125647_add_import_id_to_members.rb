class AddImportIdToMembers < ActiveRecord::Migration[8.1]
  def change
    add_reference :members, :import, foreign_key: true, null: true
  end
end
