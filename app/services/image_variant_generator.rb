# frozen_string_literal: true

class ImageVariantGenerator
  VARIANTS = {
    thumb: { resize_to_fill: [ 150, 150 ] },
    small: { resize_to_limit: [ 400, 400 ] },
    medium: { resize_to_limit: [ 800, 800 ] },
    large: { resize_to_limit: [ 1200, 1200 ] }
  }.freeze

  WEBP_QUALITY = 85  # Quality for WebP conversion
  GENERATE_WEBP = false  # Set to true when helpers support WebP

  IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp].freeze

  # Environment-aware settings
  class << self
    def concurrency_mode
      if Rails.env.production?
        :single_threaded  # Safe for production SQLite
      else
        :parallel  # Fast for development (local machine has power)
      end
    end

    def batch_size
      if Rails.env.production?
        1  # Process one at a time to avoid locks
      else
        10  # Process in batches locally
      end
    end

    def process_mode
      # In production: on-demand only (lazy)
      # In development: eager (generate immediately)
      if Rails.env.production?
        :on_demand
      else
        :eager
      end
    end

    def available?
      @available ||= begin
        # Try to require ruby-vips (won't fail if gem is installed but lib is missing)
        require "ruby-vips"

        # Test that libvips library is actually accessible
        Vips.version_string
        true
      rescue LoadError => e
        Rails.logger.info "[ImageVariants] ruby-vips gem not available: #{e.message}"
        false
      rescue NameError => e
        Rails.logger.info "[ImageVariants] libvips library not found: #{e.message}"
        false
      rescue => e
        Rails.logger.info "[ImageVariants] Image processing unavailable: #{e.message}"
        false
      end
    end

    def generate_variants(source_path, medium_id: nil)
      return false unless available?
      return false unless image_file?(source_path)

      source_path = normalize_path(source_path)
      return false unless File.exist?(source_path)

      # Skip if all variants exist and are up-to-date
      return true if variants_exist?(source_path) && !force_regenerate?(source_path)

      Rails.logger.info "[ImageVariants] Processing #{source_path}"

      # Ensure variants directory exists
      variants_dir = File.join(File.dirname(source_path), "variants")
      FileUtils.mkdir_p(variants_dir)

      # Always sequential - simple and safe
      VARIANTS.each do |name, operations|
        generate_variant(source_path, name, operations)
      end

      Rails.logger.info "[ImageVariants] ✓ Complete: #{File.basename(source_path)}"
      true
    rescue => e
      Rails.logger.error "[ImageVariants] Failed #{source_path}: #{e.message}"
      false
    end

    def generate_variants_sequential(source_path)
      VARIANTS.each do |name, operations|
        generate_variant(source_path, name, operations)
      end
    end

    def generate_variants_parallel(source_path)
      threads = VARIANTS.map do |name, operations|
        Thread.new do
          generate_variant(source_path, name, operations)
        end
      end
      threads.each(&:join)
    end

    def variant_exists?(source_path, variant_name)
      path = variant_path_for(source_path, variant_name)
      File.exist?(path)
    end

    def variant_path_for(source_path, variant_name)
      source_path = normalize_path(source_path)
      dir = File.dirname(source_path)
      base = File.basename(source_path, ".*")
      ext = File.extname(source_path)
      File.join(dir, "variants", "#{base}-#{variant_name}#{ext}")
    end

    def queue_missing_variants
      return 0 unless available?

      image_paths = Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media/images/**/*.{jpg,jpeg,png,gif,webp}"))
                       .reject { |p| p.include?("/variants/") }

      queued_count = 0
      image_paths.each do |path|
        relative_path = path.sub(RoeSitePaths::SITE_PATH.to_s, "")
        web_path = relative_path.start_with?("/") ? relative_path : "/#{relative_path}"

        unless variants_exist?(path)
          GenerateImageVariantsJob.perform_later(web_path, nil)
          queued_count += 1
        end
      end

      Rails.logger.info "[ContentSync] Queued #{queued_count} images for variant generation"
      queued_count
    end

    def stats_for(medium)
      return nil unless medium&.image?

      source_path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, "")).to_s
      {
        total: VARIANTS.count,
        generated: VARIANTS.count { |name, _| variant_exists?(source_path, name) },
        missing: VARIANTS.keys.reject { |name| variant_exists?(source_path, name) },
        ready: variants_exist?(source_path)
      }
    end

    def variants_exist?(source_path)
      source_path = normalize_path(source_path)
      VARIANTS.keys.all? { |name| variant_exists?(source_path, name) }
    end

    def normalize_path(path)
      # Handle both web paths (/media/images/...) and absolute paths
      path = path.to_s

      # If already an absolute path to site directory, use it
      if path.start_with?(RoeSitePaths::SITE_PATH.to_s)
        path
      # If it's a web path starting with /media
      elsif path.start_with?("/media/")
        File.join(RoeSitePaths::SITE_PATH, path.sub(%r{^/}, "")).to_s
      # If it starts with Rails.root
      elsif path.start_with?(Rails.root.to_s)
        path
      # Otherwise assume it's relative
      else
        File.join(RoeSitePaths::SITE_PATH, path).to_s
      end
    end

    def image_file?(path)
      IMAGE_EXTENSIONS.include?(File.extname(path).downcase)
    end

    private

    def force_regenerate?(source_path)
      # Check if variants are older than source file
      source_mtime = File.mtime(source_path)
      VARIANTS.keys.any? do |name|
        path = variant_path_for(source_path, name)
        !File.exist?(path) || File.mtime(path) < source_mtime
      end
    end

    def generate_variant(source_path, variant_name, operations)
      variant_path = variant_path_for(source_path, variant_name)

      # Skip if variant exists and is newer than source
      if File.exist?(variant_path) && File.mtime(variant_path) >= File.mtime(source_path)
        Rails.logger.debug "[ImageVariants] Skipping #{variant_name} (up to date)"
        return
      end

      # Require here instead of at top of file
      require "image_processing/vips"

      pipeline = ImageProcessing::Vips.source(source_path)
      operations.each do |operation, args|
        pipeline = pipeline.public_send(operation, *args)
      end

      # Generate main variant
      pipeline.call(destination: variant_path)

      # Generate WebP variant only if enabled
      if GENERATE_WEBP
        webp_path = variant_path.sub(File.extname(variant_path), ".webp")
        ImageProcessing::Vips.source(source_path)
                            .public_send(operations.keys.first, *operations.values.first)
                            .convert("webp")
                            .saver(quality: WEBP_QUALITY)
                            .call(destination: webp_path)
      end
    rescue => e
      Rails.logger.error "[ImageVariants] Failed to generate #{variant_name} for #{source_path}: #{e.message}"
    end

    def mark_complete(medium_id)
      Medium.find_by(id: medium_id)&.update(
        variants_status: "complete",
        variants_generated_at: Time.current
      )
    end
  end
end
