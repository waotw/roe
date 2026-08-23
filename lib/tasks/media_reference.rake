namespace :media do
  desc "Rebuild media references and recompute which files are protected"
  task backfill_references: :environment do
    puts "🔗 Rebuilding media references..."

    # The index only updates when content is saved, so an install that had
    # content before this feature landed has no references for its pages and
    # products, and stale audiences on its media. Everything below runs the
    # same code a save runs — update_media_references, which recomputes each
    # touched file's audience.
    #
    # Run this once after upgrading, or any time the index looks wrong.
    models = [ Post, Page, Product ]
    total = models.sum(&:count)
    processed = 0

    models.each do |model|
      model.find_each do |record|
        record.send(:update_media_references)
        processed += 1
        print "\r  Progress: #{processed}/#{total}" if processed % 10 == 0
      end
    end

    puts "\r  Progress: #{processed}/#{total}"
    puts
    puts "  References: #{MediaReference.group(:referenceable_type).count.inspect}"
    puts "  Protected:  #{Medium.paid.count} of #{Medium.count} files"

    mixed = Medium.mixed_audience_ids
    if mixed.any?
      puts
      puts "  ⚠ #{mixed.size} file(s) are used by BOTH paid and free content, so they"
      puts "    stay public. Find them with the Paid + Free toggles on the media page:"
      Medium.where(id: mixed).limit(10).pluck(:file_path).each { |path| puts "      #{path}" }
      puts "      …" if mixed.size > 10
    end

    puts "\n✅ Done."
  end

  desc "Show media reference statistics"
  task stats: :environment do
    puts "📊 Media Reference Statistics\n\n"
    puts "Total posts: #{Post.count}"
    puts "Posts with media: #{Post.joins(:media_references).distinct.count}"
    puts "Total media files: #{Medium.count}"
    puts "Used media files: #{Medium.joins(:media_references).distinct.count}"
    puts "Unused media files: #{Medium.unused.count}"
    puts "\nTop posts by media count:"
    Post.joins(:media_references)
        .select("posts.*, COUNT(media_references.id) as media_count")
        .group("posts.id")
        .order("media_count DESC")
        .limit(5)
        .each do |post|
          puts "  - #{post.title}: #{post.media_count} files"
        end
  end
end
