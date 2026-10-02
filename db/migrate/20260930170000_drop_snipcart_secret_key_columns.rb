class DropSnipcartSecretKeyColumns < ActiveRecord::Migration[8.1]
  # Remove the unused secret_key_live / secret_key_test columns from
  # snipcart_configs. These are the tail of the api_key_* → secret_key_*
  # rename (20260619212000): the rename carried the columns forward, but
  # nothing ever read or wrote them. Snipcart only needs its PUBLIC API
  # key (embedded in the page by design); the secret key is for their
  # REST API (order queries, refunds, server-side webhook validation),
  # none of which Roe does — webhooks are authed by an unguessable token
  # in the URL path instead. Carrying empty secret columns implies a
  # credential is in play when none is, which is why they aren't even
  # encrypted. Drop them.
  #
  # Idempotent — guarded by column_exists? so re-runs and installs that
  # already lack the columns both behave correctly.
  def up
    %i[secret_key_test secret_key_live].each do |col|
      remove_column :snipcart_configs, col if column_exists?(:snipcart_configs, col)
    end
  end

  def down
    # The columns held no data (nothing ever wrote them), so there is
    # nothing to restore. Re-add them empty so the migration is
    # structurally reversible.
    %i[secret_key_test secret_key_live].each do |col|
      add_column :snipcart_configs, col, :text unless column_exists?(:snipcart_configs, col)
    end
  end
end
