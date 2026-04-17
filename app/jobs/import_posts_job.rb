class ImportPostsJob < ApplicationJob
  queue_as :default

  def perform(import_id)
    import = Import.find(import_id)
    importer = SubstackImporter::PostsImporter.new(import)
    importer.run
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[ImportPostsJob] Import #{import_id} not found"
  rescue => e
    Rails.logger.error "[ImportPostsJob] Job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Try to mark import as failed
    begin
      import = Import.find_by(id: import_id)
      import&.mark_failed!(e.message)
    rescue => e2
      Rails.logger.error "[ImportPostsJob] Failed to mark import as failed: #{e2.message}"
    end
  end
end
