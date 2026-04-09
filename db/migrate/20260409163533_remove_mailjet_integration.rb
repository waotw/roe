class RemoveMailjetIntegration < ActiveRecord::Migration[8.0]
  def change
    # Drop mailjet_configs table
    drop_table :mailjet_configs, if_exists: true

    # Remove mailjet_contact_id from members
    remove_column :members, :mailjet_contact_id, :string, if_exists: true

    # Rename mailjet_message_id to message_id in newsletter_sends
    # (You're still using this for Postmark!)
    rename_column :newsletter_sends, :mailjet_message_id, :message_id if column_exists?(:newsletter_sends, :mailjet_message_id)
  end
end
