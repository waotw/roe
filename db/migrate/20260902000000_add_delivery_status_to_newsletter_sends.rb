class AddDeliveryStatusToNewsletterSends < ActiveRecord::Migration[8.1]
  # Record failed sends, not just successful ones.
  #
  # A row existed only when Postmark accepted a message, and the admin panel
  # counts rows — so forty failures out of a hundred read as "Newsletter sent
  # to 60 members", with the other forty existing only as a log line nobody
  # tails. That's the silent failure.
  #
  # sent_at stays NOT NULL for successes, so a failure row records when it was
  # attempted instead.
  def change
    add_column :newsletter_sends, :status, :string, null: false, default: "sent"
    add_column :newsletter_sends, :error, :string
    add_column :newsletter_sends, :attempted_at, :datetime

    # sent_at is NOT NULL, which a failed send can't satisfy — it was never
    # sent. Relaxing it lets one table hold both outcomes rather than adding a
    # second table that has to be joined everywhere sends are counted.
    change_column_null :newsletter_sends, :sent_at, true

    add_index :newsletter_sends, [ :post_id, :status ]
  end
end
