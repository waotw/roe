# frozen_string_literal: true

namespace :images do
  desc "Generate variants for all images missing them"
  task generate_variants: :environment do
    unless ImageVariantGenerator.available?
      puts "❌ ImageVariantGenerator not available. Install libvips: brew install vips"
      exit 1
    end

    queued = ImageVariantGenerator.queue_missing_variants
    puts "✓ Queued #{queued} images for variant generation"
    puts "  Variants will be created in: /site/media/images/variants/"
    puts "  Run 'bin/jobs' to process the queue"
  end

  desc "Regenerate all variants (force)"
  task regenerate_variants: :environment do
    unless ImageVariantGenerator.available?
      puts "❌ ImageVariantGenerator not available. Install libvips: brew install vips"
      exit 1
    end

    image_paths = Dir.glob(Rails.root.join("site/media/images/**/*.{jpg,jpeg,png,gif,webp}"))
                     .reject { |p| p.include?("/variants/") }

    puts "🖼️  Found #{image_paths.count} images"
    puts "⚠️  This will DELETE all existing variants and regenerate them."
    print "Continue? (y/N): "

    response = STDIN.gets.chomp
    unless response.downcase == 'y'
      puts "Cancelled."
      exit 0
    end

    # Clear existing variants first
    variants_dir = Rails.root.join("site/media/images/variants")
    if Dir.exist?(variants_dir)
      puts "🧹 Clearing existing variants..."
      FileUtils.rm_rf(variants_dir)
      FileUtils.mkdir_p(variants_dir)
    end

    # Reset all media records
    Medium.where(media_type: "images").update_all(variants_status: "pending", variants_generated_at: nil)

    # Queue all images
    image_paths.each do |path|
      relative_path = path.sub(Rails.root.join("site").to_s, "")
      web_path = relative_path.start_with?("/") ? relative_path : "/#{relative_path}"
      GenerateImageVariantsJob.perform_later(web_path, nil)
    end

    puts "✓ Queued #{image_paths.count} images for regeneration"
    puts "  Run 'bin/jobs' to process the queue"
  end

  desc "Check variant status for all images"
  task status: :environment do
    images = Medium.images
    total = images.count
    complete = images.with_complete_variants.count
    pending = images.with_pending_variants.count

    puts "\n📊 Image Variant Status"
    puts "=" * 50
    puts "Total images: #{total}"
    puts "Complete:     #{complete} (#{(complete.to_f / total * 100).round(1)}%)"
    puts "Pending:      #{pending}"

    if pending > 0
      puts "\n⏳ Pending images:"
      images.with_pending_variants.limit(10).each do |img|
        puts "  - #{File.basename(img.file_path)}"
      end
      puts "  ... and #{pending - 10} more" if pending > 10
    end

    puts ""

    unless ImageVariantGenerator.available?
      puts "⚠️  ImageMagick not installed - variant generation disabled"
      puts "   Install with: brew install imagemagick"
    end
  end

  desc "Clean up orphaned variant files"
  task cleanup: :environment do
    variants_dir = Rails.root.join("site/media/images/variants")
    return unless Dir.exist?(variants_dir)

    variant_files = Dir.glob(variants_dir.join("*"))
    originals_dir = Rails.root.join("site/media/images")

    removed = 0
    variant_files.each do |variant_file|
      # Extract original filename from variant filename
      basename = File.basename(variant_file)
      # Remove variant suffix (e.g., "-medium", "-thumb") to find original
      original_name = basename.sub(/-(thumb|small|medium|large)\.(jpg|jpeg|png|gif|webp)$/, '.\\2')
      original_path = originals_dir.join(original_name)

      unless File.exist?(original_path)
        File.delete(variant_file)
        removed += 1
        puts "🗑️  Removed orphaned variant: #{basename}"
      end
    end

    puts "\n✓ Removed #{removed} orphaned variant files"
  end
end
