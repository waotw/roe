class AddSnippetToSnipcartConfigs < ActiveRecord::Migration[8.1]
  def change
    add_column :snipcart_configs, :snippet, :text
  end
end
