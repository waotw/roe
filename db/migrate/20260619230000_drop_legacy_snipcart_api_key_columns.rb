class DropLegacySnipcartApiKeyColumns < ActiveRecord::Migration[8.1]
  # Safety net for installs whose snipcart_configs table drifted out of
  # sync with schema.rb during the api_key_* → secret_key_* rename in
  # 20260619212000. On a clean install the rename migration removes the
  # old columns as part of its work, so this migration finds nothing to
  # drop and runs as a no-op. On drifted installs (where the rename left
  # both old and new columns side-by-side — observed in dev DBs where
  # the model was loaded mid-migration), this drops the orphaned old
  # columns so the table matches schema.rb.
  #
  # Idempotent — guarded by column_exists? so re-runs and clean installs
  # both behave correctly.
  def up
    %i[api_key_test api_key_live].each do |col|
      remove_column :snipcart_configs, col if column_exists?(:snipcart_configs, col)
    end
  end

  def down
    # Any data in the old columns at the drifted-DB time was nil (drift
    # happens before the rename completes copying data), so there's
    # nothing to restore. Re-add the empty columns so the rollback is
    # structurally reversible if the rename above is also rolled back.
    %i[api_key_test api_key_live].each do |col|
      add_column :snipcart_configs, col, :text unless column_exists?(:snipcart_configs, col)
    end
  end
end
