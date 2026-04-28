class AddRssDataToImports < ActiveRecord::Migration[8.1]
  def change
    # Holds parsed RSS feed data (channel + items) for the duration of an
    # import run. Scrubbed (set to nil) once the import completes — the
    # data contains token-bearing enclosure URLs we don't want lingering.
    add_column :imports, :rss_data, :json
  end
end
