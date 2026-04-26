class AddRefundTrackingToDonationsAndMembers < ActiveRecord::Migration[8.1]
  def change
    add_column :donations, :refunded_at, :datetime
    add_column :donations, :refunded_amount_cents, :integer
    add_column :donations, :refunded_currency, :string

    add_column :members, :refunded_at, :datetime
    add_column :members, :refunded_amount_cents, :integer
    add_column :members, :refunded_currency, :string
  end
end
