class AddAudienceToMedia < ActiveRecord::Migration[8.1]
  # Cached answer to "is this file protected?", recomputed whenever content
  # that references it is saved. The alternative — joining media_references to
  # posts and pages on every request — runs on every image on every page.
  #
  # "free" wins over "paid" when a file is referenced by both: editing an
  # unrelated paid post must never silently break an image on a public page.
  def change
    add_column :media, :audience, :string, default: "free", null: false
    add_index :media, :audience
  end
end
