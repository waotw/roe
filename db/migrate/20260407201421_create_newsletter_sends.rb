class CreateNewsletterSends < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletter_sends do |t|
      t.integer :post_id, null: false
      t.integer :member_id, null: false
      t.datetime :sent_at, null: false
      t.string :mailjet_message_id

      t.timestamps
    end

    add_index :newsletter_sends, :post_id
    add_index :newsletter_sends, :member_id
    add_index :newsletter_sends, [:post_id, :member_id], unique: true
    add_index :newsletter_sends, :mailjet_message_id
  end
end
