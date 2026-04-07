class AddNewsletterStatusToMembers < ActiveRecord::Migration[7.2]
  def change
    add_column :members, :newsletter_status, :integer, default: 0, null: false
    add_column :members, :mailjet_contact_id, :string
    add_index :members, :mailjet_contact_id
  end
end
