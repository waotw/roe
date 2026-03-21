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
end
