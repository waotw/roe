namespace :content do
  def app_name
    ENV['FLY_APP_NAME'] || 'roe'
  end

  def machine_id
    machines = `fly machine list --json -a #{app_name}`.strip
    JSON.parse(machines).first['id']
  rescue
    puts "❌ Could not get machine ID"
    exit 1
  end

  desc "Sync site folder with production (bidirectional)"
  task :sync_site do
    machine = machine_id
    puts "🔄 Syncing site with #{app_name} (#{machine})..."

    # Pull from production (files newer on remote)
    puts "\n📥 Pulling changes from production..."
    system("rsync -rltzPi -e ./bin/fly-rsync #{machine}:/data/site/ ./site/")

    # Push to production (files newer locally)
    puts "\n📤 Pushing local changes..."
    system("rsync -rltzPi -e ./bin/fly-rsync ./site/ #{machine}:/data/site/")

    puts "\n✅ Sync complete!"
  end

  desc "Push site folder to production"
  task :push_site do
    machine = machine_id
    puts "📤 Pushing site to #{app_name} (#{machine})..."
    system("rsync -rltzPi -e ./bin/fly-rsync ./site/ #{machine}:/data/site/")
    puts "✅ Push complete!"
  end

  desc "Pull site folder from production"
  task :pull_site do
    machine = machine_id
    puts "📥 Pulling site from #{app_name} (#{machine})..."
    system("rsync -rltzPi -e ./bin/fly-rsync #{machine}:/data/site/ ./site/")
    puts "✅ Pull complete!"
  end

  # NEW: Backup production to timestamped folder
  desc "Backup production site to timestamped folder"
  task :backup_site do
    machine = machine_id
    timestamp = Time.now.strftime("%Y-%m-%d-%H%M%S")
    backup_dir = "./site_backups/#{timestamp}"

    FileUtils.mkdir_p(backup_dir)

    puts "💾 Backing up #{app_name} to #{backup_dir}..."
    system("rsync -rltzPi -e ./bin/fly-rsync #{machine}:/data/site/ #{backup_dir}/")
    puts "✅ Backup saved to: #{backup_dir}"
  end

  desc "Push specific folders to production (e.g., rake content:push_folders[posts,theme])"
  task :push_folders, [:folders] do |t, args|
    unless args[:folders]
      puts "❌ Usage: rake content:push_folders[posts,theme]"
      exit 1
    end

    machine = machine_id
    folders = args[:folders].split(',')

    puts "📤 Pushing #{folders.join(', ')} to #{app_name} (#{machine})..."
    puts "⚠️  This will OVERWRITE these folders on production!"
    print "Type 'yes' to confirm: "

    confirmation = STDIN.gets.chomp
    unless confirmation == 'yes'
      puts "❌ Aborted"
      exit 0
    end

    folders.each do |folder|
      folder = folder.strip
      local_path = "./site/#{folder}/"
      remote_path = "#{machine}:/data/site/#{folder}/"

      unless Dir.exist?(local_path)
        puts "⚠️  Skipping #{folder} (not found locally)"
        next
      end

      puts "\n  → Syncing #{folder}/"
      system("rsync -rltzPi --delete -e ./bin/fly-rsync #{local_path} #{remote_path}")
    end

    puts "\n✅ Push complete!"
  end

  # NEW: List what would change (dry-run)
  desc "Preview changes between local and production"
  task :preview_changes do
    machine = machine_id
    puts "📋 Previewing changes (dry-run)..."
    puts "\n--- Files that would be pulled FROM production ---"
    system("rsync -rltzPin --dry-run -e ./bin/fly-rsync #{machine}:/data/site/ ./site/")
    puts "\n--- Files that would be pushed TO production ---"
    system("rsync -rltzPin --dry-run -e ./bin/fly-rsync ./site/ #{machine}:/data/site/")
  end

  # Add this to lib/tasks/content.rake

  desc "Rollback production site to a previous backup"
  task :rollback_site do
    backups = Dir.glob("./site_backups/*/").sort.reverse

    if backups.empty?
      puts "❌ No backups found in site_backups/"
      exit 1
    end

    puts "📂 Available backups:"
    backups.each_with_index do |backup, i|
      timestamp = File.basename(backup)
      size = `du -sh #{backup}`.split.first
      puts "  #{i + 1}) #{timestamp} (#{size})"
    end

    print "\nChoose backup to restore (1-#{backups.length}): "
    choice = STDIN.gets.chomp.to_i

    unless choice.between?(1, backups.length)
      puts "❌ Invalid choice"
      exit 1
    end

    backup_dir = backups[choice - 1]
    timestamp = File.basename(backup_dir)

    puts "\n⚠️  This will OVERWRITE production with backup: #{timestamp}"
    print "Type 'yes' to confirm: "

    unless STDIN.gets.chomp == 'yes'
      puts "❌ Rollback cancelled"
      exit 0
    end

    machine = machine_id
    puts "\n⏮️  Rolling back production to #{timestamp}..."
    system("rsync -rltzPi --delete -e ./bin/fly-rsync #{backup_dir} #{machine}:/data/site/")
    puts "✅ Rollback complete!"
  end
end
