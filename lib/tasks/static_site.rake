namespace :site do
  desc "Generate static site"
  task generate: :environment do
    puts "🚀 Starting static site generation..."
    puts ""

    generator = StaticGenerator.new
    stats = generator.generate_all

    puts ""
    if stats[:errors].empty?
      puts "✅ Static site generated successfully!"
    else
      puts "⚠️  Static site generated with #{stats[:errors].count} errors"
      puts ""
      puts "Errors:"
      puts "=" * 60
      stats[:errors].each_with_index do |error, i|
        identifier = error[:identifier] ? " (#{error[:identifier]})" : ""
        puts "#{i + 1}. #{error[:type]}#{identifier}"
        puts "   #{error[:message]}"
        puts ""
      end
      puts "=" * 60
      exit 1
    end
  end

  desc "Generate static site to custom directory"
  task :generate_to, [ :output_dir ] => :environment do |t, args|
    output_dir = args[:output_dir] || Rails.root.join('tmp', 'static_site')

    puts "🚀 Generating static site to: #{output_dir}"
    puts ""

    generator = StaticGenerator.new(output_dir: output_dir)
    stats = generator.generate_all

    puts ""
    if stats[:errors].empty?
      puts "✅ Static site generated successfully!"
    else
      puts "⚠️  Static site generated with #{stats[:errors].count} errors"
      puts ""
      puts "Errors:"
      puts "=" * 60
      stats[:errors].each_with_index do |error, i|
        identifier = error[:identifier] ? " (#{error[:identifier]})" : ""
        puts "#{i + 1}. #{error[:type]}#{identifier}"
        puts "   #{error[:message]}"
        puts ""
      end
      puts "=" * 60
      exit 1
    end
  end

  desc "Preview static site locally"
  task preview: :generate do
    puts ""
    puts "🌐 Starting local preview server..."
    puts "   Visit: http://localhost:8080"
    puts "   Press Ctrl+C to stop"
    puts ""

    require 'webrick'

    server = WEBrick::HTTPServer.new(
      Port: 8080,
      DocumentRoot: Rails.root.join('public'),
      Logger: WEBrick::Log.new('/dev/null'),
      AccessLog: []
    )

    trap('INT') { server.shutdown }
    server.start
  end

  desc "Clean generated static files from public directory"
  task clean: :environment do
    public_dir = Rails.root.join('public')

    files_deleted = 0

    puts "🧹 Cleaning static site files..."

    # Remove individual posts
    Dir.glob(public_dir.join('posts', '*.html')).each do |file|
      File.delete(file)
      files_deleted += 1
    end

    # Remove post pagination
    Dir.glob(public_dir.join('posts', 'page-*.html')).each do |file|
      File.delete(file)
      files_deleted += 1
    end

    # Remove collections directory
    if Dir.exist?(public_dir.join('collections'))
      collection_files = Dir.glob(public_dir.join('collections', '**', '*')).count { |f| File.file?(f) }
      FileUtils.rm_rf(public_dir.join('collections'))
      files_deleted += collection_files
    end

    # Remove documentation pages
    if Dir.exist?(public_dir.join('documentation'))
      doc_files = Dir.glob(public_dir.join('documentation', '**', '*')).count { |f| File.file?(f) }
      FileUtils.rm_rf(public_dir.join('documentation'))
      files_deleted += doc_files
    end

    # Remove page files (but keep index.html)
    Dir.glob(public_dir.join('*.html')).each do |file|
      next if File.basename(file) == 'index.html'
      File.delete(file)
      files_deleted += 1
    end

    # Remove feeds
    [ 'feed.rss', 'feed.atom' ].each do |feed|
      if File.exist?(public_dir.join(feed))
        File.delete(public_dir.join(feed))
        files_deleted += 1
      end
    end

    # Remove podcast feeds
    if Dir.exist?(public_dir.join('podcast'))
      podcast_files = Dir.glob(public_dir.join('podcast', '*.xml')).count
      FileUtils.rm_rf(public_dir.join('podcast'))
      files_deleted += podcast_files
    end

    # Remove manifest (forces full regeneration)
    if File.exist?(public_dir.join('.generation_manifest.json'))
      File.delete(public_dir.join('.generation_manifest.json'))
      puts "   ✓ Deleted generation manifest"
    end

    puts "   ✓ Cleaned #{files_deleted} static files"
    puts ""
  end

  desc "Clean and regenerate the entire static site"
  task rebuild: :environment do
    Rake::Task['site:clean'].invoke
    Rake::Task['site:generate'].invoke
  end
end
