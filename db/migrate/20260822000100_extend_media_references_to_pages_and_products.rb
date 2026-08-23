class ExtendMediaReferencesToPagesAndProducts < ActiveRecord::Migration[8.1]
  # media_references linked media to POSTS only (post_id NOT NULL), so a file
  # used by a page or a product looked unreferenced. That matters now that the
  # index decides whether a file is protected: a paid page's audio would have
  # been served to anyone.
  #
  # Goes polymorphic rather than adding page_id/product_id columns, so a fourth
  # content type later is a row value rather than another migration.
  def up
    add_column :media_references, :referenceable_type, :string
    add_column :media_references, :referenceable_id, :integer

    execute <<~SQL
      UPDATE media_references
      SET referenceable_type = 'Post', referenceable_id = post_id
    SQL

    change_column_null :media_references, :referenceable_type, false
    change_column_null :media_references, :referenceable_id, false

    remove_index :media_references, column: [ :post_id, :medium_id ]
    remove_index :media_references, column: :post_id
    remove_column :media_references, :post_id

    add_index :media_references, [ :referenceable_type, :referenceable_id ],
              name: "index_media_references_on_referenceable"
    add_index :media_references,
              [ :referenceable_type, :referenceable_id, :medium_id ],
              unique: true, name: "index_media_references_on_referenceable_and_medium"
  end

  def down
    add_column :media_references, :post_id, :integer
    execute <<~SQL
      UPDATE media_references
      SET post_id = referenceable_id
      WHERE referenceable_type = 'Post'
    SQL
    execute "DELETE FROM media_references WHERE referenceable_type != 'Post'"
    change_column_null :media_references, :post_id, false

    remove_index :media_references, name: "index_media_references_on_referenceable"
    remove_index :media_references, name: "index_media_references_on_referenceable_and_medium"
    remove_column :media_references, :referenceable_type
    remove_column :media_references, :referenceable_id

    add_index :media_references, :post_id
    add_index :media_references, [ :post_id, :medium_id ], unique: true
  end
end
