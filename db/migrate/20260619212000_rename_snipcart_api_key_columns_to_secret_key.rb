class RenameSnipcartApiKeyColumnsToSecretKey < ActiveRecord::Migration[8.1]
  def change
    rename_column :snipcart_configs, :api_key_test, :secret_key_test
    rename_column :snipcart_configs, :api_key_live, :secret_key_live
  end
end
