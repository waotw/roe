class AddImportTrackingToPosts < ActiveRecord::Migration[8.1]
  def change
    add_reference :posts, :import, foreign_key: true, null: true
  end
end
