namespace :media do
  desc "Backfill media references for existing posts"
  task backfill_references: :environment do
    puts "🔗 Backfilling media references..."

    total = Post.count
    processed = 0
    references_created = 0

    Post.find_each do |post|
      # Extract media paths from content
      media_paths = post.send(:extract_media_paths)

      if media_paths.any?
        # Find matching Medium records
        referenced_media = Medium.where(file_path: media_paths)

        # Create references
        referenced_media.each do |medium|
          unless post.media_references.exists?(medium: medium)
            post.media_references.create(medium: medium)
            references_created += 1
          end
        end

        puts "  ✓ #{post.title || post.file_path}: #{referenced_media.count} media files"
      end

      processed += 1
      print "\r  Progress: #{processed}/#{total}" if processed % 10 == 0
    end

    puts "\n\n✅ Done! Created #{references_created} references for #{total} posts"
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
        .select('posts.*, COUNT(media_references.id) as media_count')
        .group('posts.id')
        .order('media_count DESC')
        .limit(5)
        .each do |post|
          puts "  - #{post.title}: #{post.media_count} files"
        end
  end
end
