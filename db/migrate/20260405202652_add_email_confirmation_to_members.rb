class AddEmailConfirmationToMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :members, :pending_email, :string
    add_column :members, :email_confirmation_token, :string
    add_column :members, :email_confirmation_sent_at, :datetime
  end
end
