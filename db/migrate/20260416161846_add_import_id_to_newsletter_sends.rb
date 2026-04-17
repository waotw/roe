class AddImportIdToNewsletterSends < ActiveRecord::Migration[8.1]
  def change
    add_reference :newsletter_sends, :import, foreign_key: true, null: true
  end
end
