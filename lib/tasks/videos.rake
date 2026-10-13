# Web versions of videos (720p / 1080p MP4 + poster), made with ffmpeg on
# this computer. Normally they're made automatically when a video is added;
# these are for catching up on videos added before ffmpeg was installed, or
# rebuilding after the encode settings change.
namespace :videos do
  desc "Make web versions for every video that doesn't have them yet"
  task variants: :environment do
    unless VideoVariantGenerator.available?
      abort "ffmpeg isn't installed here. Run: roe install ffmpeg"
    end

    count = VideoVariantGenerator.queue_missing!
    puts "✓ Queued #{count} #{'video'.pluralize(count)} for web versions."
    puts "  They're made one at a time in the background while Roe is running."
  end

  desc "Rebuild web versions for every video (after changing encode settings)"
  task rebuild: :environment do
    abort "ffmpeg isn't installed here. Run: roe install ffmpeg" unless VideoVariantGenerator.available?

    count = VideoVariantGenerator.queue_missing!(force: true)
    puts "✓ Queued #{count} #{'video'.pluralize(count)} to rebuild."
  end

  desc "Show each video's web versions and how much smaller they are"
  task status: :environment do
    originals = VideoVariantGenerator.originals
    if originals.empty?
      puts "No videos in site/media."
      next
    end

    human = ->(bytes) { ActiveSupport::NumberHelper.number_to_human_size(bytes) }
    originals.sort.each do |path|
      manifest = VideoVariantGenerator.current_manifest(path)
      rel = VideoVariantGenerator.web_path_for(path)
      if manifest.nil?
        puts "  ○ #{rel}  #{human.(File.size(path))}  — no web versions yet"
      else
        parts = Array(manifest["renditions"]).map { |r| "#{r['name']} #{human.(r['size'])}" }
        parts << "original is served (already web-ready)" if parts.empty? && manifest["skipped"].present?
        mark = manifest["complete"] ? "✓" : "…"
        puts "  #{mark} #{rel}  #{human.(File.size(path))} → #{parts.join(', ')}"
      end
    end
  end

  desc "Remove web versions whose original video is gone"
  task prune: :environment do
    deleted = VideoVariantGenerator.prune_orphans!
    puts "✓ Removed #{deleted} orphaned video #{'file'.pluralize(deleted)}."
  end
end
