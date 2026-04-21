class GenerateImageVariantsJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: 5.seconds, attempts: 3 do |job, exception|
    if Rails.env.development?
      puts "\n" + "=" * 80
      puts "💥 JOB FAILED: #{job.class.name}"
      puts "=" * 80
      puts "Arguments: #{job.arguments.inspect}"
      puts "Error: #{exception.class}: #{exception.message}"
      puts exception.backtrace.first(10).join("\n")
      puts "=" * 80 + "\n"
    end
  end

  def perform(file_path, medium_id)
    return if Rails.env.production?

    Rails.logger.info "[ImageVariants] Job started: #{file_path}"

    normalized_path = ImageVariantGenerator.normalize_path(file_path)

    unless File.exist?(normalized_path)
      Rails.logger.warn "[ImageVariants] File not found: #{normalized_path}"
      return
    end

    unless ImageVariantGenerator.image_file?(normalized_path)
      Rails.logger.warn "[ImageVariants] Not an image file: #{normalized_path}"
      return
    end

    if ImageVariantGenerator.process_mode == :on_demand
      if ImageVariantGenerator.variants_exist?(normalized_path)
        Rails.logger.info "[ImageVariants] Variants already exist, skipping: #{file_path}"
        return
      end
    end

    result = ImageVariantGenerator.generate_variants(normalized_path, medium_id: nil)
    Rails.logger.info "[ImageVariants] Job #{result ? 'completed' : 'failed'}: #{file_path}"
  rescue => e
    if Rails.env.development?
      puts "\n" + "=" * 80
      puts "💥 ERROR IN JOB: #{self.class.name}"
      puts "=" * 80
      puts "File: #{file_path}"
      puts "Error: #{e.class}: #{e.message}"
      puts e.backtrace.first(15).join("\n")
      puts "=" * 80 + "\n"
    end
    raise
  end
end
