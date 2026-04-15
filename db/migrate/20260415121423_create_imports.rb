class CreateImports < ActiveRecord::Migration[8.1]
  def change
    create_table :imports do |t|
      t.string :source_type, null: false, default: 'substack'
      t.integer :status, null: false, default: 0
      t.integer :phase, null: false, default: 1
      t.string :archive_file
      t.json :configuration, default: {}
      t.json :stats, default: {}
      t.json :original_data, default: {}
      t.json :completed_phases, default: []
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :imports, :status
    add_index :imports, :phase
    add_index :imports, :created_at
  end
end
