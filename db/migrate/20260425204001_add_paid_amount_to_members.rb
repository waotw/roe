class AddPaidAmountToMembers < ActiveRecord::Migration[8.1]
  def change
    # Snapshot of the membership upgrade price at the moment of payment.
    # Nullable for back-compat (existing paid members predate this column).
    add_column :members, :paid_amount_cents, :integer
    add_column :members, :paid_currency, :string
  end
end
