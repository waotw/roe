# Simple class to mimic ActionDispatch::Http::UploadedFile
class TempUploadedFile
  attr_reader :path, :original_filename

  def initialize(path, original_filename)
    @path = path
    @original_filename = original_filename
  end

  def read
    File.read(@path)
  end
end

class BulkUploadJob < ApplicationJob
  queue_as :default

  def perform(batch_id, temp_files)
    sleep(2)

    # Give the browser time to establish Turbo Stream connection
    sleep(1) unless Rails.env.development?

    temp_files.each_with_index do |file_info, index|
      begin
        # Broadcast uploading status
        broadcast_status(batch_id, index, "⏳", "Uploading...")
        sleep(0.3) unless Rails.env.development?

        # Create a simple object that mimics UploadedFile
        uploaded_file = TempUploadedFile.new(
          file_info[:temp_path],
          file_info[:original_filename]
        )

        # Process the upload
        medium = Admin::MediumController.new.send(:process_single_upload, uploaded_file)

        # Queue variant generation if it's an image
        if medium.image? && ImageVariantGenerator.available?
          broadcast_status(batch_id, index, "🔄", "Optimizing...")
          GenerateImageVariantsJob.perform_later(medium.file_path, medium.id)
        end

        # Broadcast success
        broadcast_status(batch_id, index, "✅", "Complete")

      rescue => e
        Rails.logger.error "[BulkUpload] Failed: #{e.message}"
        broadcast_status(batch_id, index, "❌", "Failed: #{e.message}")
      ensure
        # Clean up temp file
        File.delete(file_info[:temp_path]) if File.exist?(file_info[:temp_path])
      end
    end

    # Clean up temp directory
    temp_dir = File.dirname(temp_files.first[:temp_path])
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)

    # Broadcast completion
    broadcast_completion(batch_id)
  end

  private

  def broadcast_status(batch_id, file_index, icon, message)
    Turbo::StreamsChannel.broadcast_update_to(
      "upload_batch_#{batch_id}",
      target: "file-#{file_index}-status",
      html: icon
    )

    # Small delay to ensure broadcasts are processed separately
    sleep(0.1) unless Rails.env.development?

    Turbo::StreamsChannel.broadcast_update_to(
      "upload_batch_#{batch_id}",
      target: "file-#{file_index}-message",
      html: "<span class='text-xs text-gray-600'>#{message}</span>"
    )
  end

  def broadcast_completion(batch_id)
    Turbo::StreamsChannel.broadcast_update_to(  # Should be broadcast_update_to
      "upload_batch_#{batch_id}",
      target: "completion-actions",
      html: <<~HTML
        <p class="text-sm text-green-700 mb-4">✅ All files uploaded successfully!</p>
        <a href="/admin/medium/browse" class="inline-flex items-center uppercase text-sm px-1.5 py-0.5 border border-green-800 bg-green-200 hover:bg-green-300 font-mono rounded-xs">
          Back to Media Library
        </a>
      HTML
    )
  end
end
