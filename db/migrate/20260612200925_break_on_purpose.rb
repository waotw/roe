class BreakOnPurpose < ActiveRecord::Migration[8.0]
  def change
    # References a table that doesn't exist — db:migrate raises.
    add_column :totally_nonexistent_table, :foo, :string
  end
end
