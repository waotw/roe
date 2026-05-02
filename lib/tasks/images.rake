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

    image_paths = Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media/images/**/*.{jpg,jpeg,png,gif,webp,heic,heif}"))
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
    variants_dir = File.join(RoeSitePaths::SITE_PATH, "media/images/variants")
    if Dir.exist?(variants_dir)
      puts "🧹 Clearing existing variants..."
      FileUtils.rm_rf(variants_dir)
      FileUtils.mkdir_p(variants_dir)
    end

    # Reset all media records
    Medium.where(media_type: "images").update_all(variants_status: "pending", variants_generated_at: nil)

    # Queue all images
    image_paths.each do |path|
      relative_path = path.sub(RoeSitePaths::SITE_PATH.to_s, "")
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
    variants_dir = File.join(RoeSitePaths::SITE_PATH, "media/images/variants")
    next unless Dir.exist?(variants_dir)

    variant_files = Dir.glob(File.join(variants_dir, "*"))
    originals_dir = File.join(RoeSitePaths::SITE_PATH, "media/images")

    removed = 0
    variant_files.each do |variant_file|
      basename = File.basename(variant_file)
      # Strip the variant suffix to recover the source's base name. We
      # look up the original by base name across every supported source
      # extension because HEIC sources produce .jpg variants — comparing
      # the variant's extension to the original's would falsely flag
      # those as orphans.
      base_match = basename.match(/\A(.+)-(?:thumb|small|medium|large)\.[^.]+\z/)
      next unless base_match

      base_name = base_match[1]
      original_exists = ImageVariantGenerator::IMAGE_EXTENSIONS.any? do |ext|
        File.exist?(File.join(originals_dir, "#{base_name}#{ext}"))
      end

      unless original_exists
        File.delete(variant_file)
        removed += 1
        puts "🗑️  Removed orphaned variant: #{basename}"
      end
    end

    puts "\n✓ Removed #{removed} orphaned variant files"
  end

  desc "Backfill variants_status from filesystem (run once after enabling DB-backed status)"
  task backfill_status: :environment do
    fixed = 0
    Medium.images.find_each do |medium|
      source_path = File.join(RoeSitePaths::SITE_PATH, medium.file_path.sub(%r{^/}, "")).to_s
      complete = File.exist?(source_path) && ImageVariantGenerator.variants_exist?(source_path)
      target_status = complete ? "complete" : "pending"
      target_generated_at = complete ? File.mtime(source_path) : nil

      next if medium.variants_status == target_status &&
              medium.variants_generated_at.to_i == target_generated_at.to_i

      medium.update_columns(
        variants_status: target_status,
        variants_generated_at: target_generated_at
      )
      fixed += 1
    end

    puts "✓ Backfilled #{fixed} Medium record(s) from filesystem state"
  end
end
