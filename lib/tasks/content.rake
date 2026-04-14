namespace :site do
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

  # desc "Sync site folder with production (bidirectional)"
  # task :sync do
  #   machine = machine_id
  #   puts "🔄 Syncing site with #{app_name} (#{machine})..."

  #   # Pull from production (files newer on remote)
  #   puts "\n📥 Pulling changes from production..."
  #   system("rsync -rltzPi -e ./bin/fly-rsync #{machine}:/data/site/ ./site/")

  #   # Push to production (files newer locally)
  #   puts "\n📤 Pushing local changes..."
  #   system("rsync -rltzPi -e ./bin/fly-rsync ./site/ #{machine}:/data/site/")

  #   puts "\n✅ Sync complete!"
  # end

  desc "Push site folder to production"
  task :push do
    machine = machine_id
    puts "📤 Pushing site to #{app_name} (#{machine})..."
    puts "⚠️  This will OVERWRITE all content on production!"
    print "Type 'yes' to confirm: "

    confirmation = STDIN.gets.chomp
    unless confirmation == 'yes'
      puts "❌ Aborted"
      exit 0
    end

    system("rsync -rltzPi -e ./bin/fly-rsync ./site/ #{machine}:/data/site/")
    puts "✅ Push complete!"
  end

  desc "Backup production site with incremental hard-link snapshots (keeps 15)"
  task :backup do
    machine = machine_id
    timestamp = Time.now.strftime("%Y-%m-%d-%H%M%S")
    backup_dir = "./site_backups/#{timestamp}"

    # Find most recent backup for hard-linking
    previous_backups = Dir.glob("./site_backups/20*").sort
    previous_backup = previous_backups.last

    # Build rsync command
    rsync_cmd = "rsync -avP"

    # Add --link-dest if we have a previous backup
    if previous_backup
      # Use absolute path for --link-dest
      link_dest_path = File.expand_path(previous_backup)
      rsync_cmd += " --link-dest=#{link_dest_path}"
      puts "💾 Creating incremental backup: #{timestamp}"
      puts "   Linking to: #{File.basename(previous_backup)}"
    else
      puts "💾 Creating first full backup: #{timestamp}"
    end

    # Create backup directory
    FileUtils.mkdir_p(backup_dir)

    # Execute rsync
    rsync_cmd += " -e ./bin/fly-rsync #{machine}:/data/site/ #{backup_dir}/"
    system(rsync_cmd)

    # Update 'latest' symlink
    latest_link = "./site_backups/latest"
    FileUtils.rm_f(latest_link) if File.symlink?(latest_link)
    FileUtils.ln_s(timestamp, latest_link)
    puts "   Updated: site_backups/latest → #{timestamp}"

    # Cleanup: keep only 15 most recent backups
    all_backups = Dir.glob("./site_backups/20*").sort
    if all_backups.length > 15
      to_delete = all_backups[0...(all_backups.length - 15)]
      puts "\n🗑️  Removing #{to_delete.length} old backup(s):"
      to_delete.each do |old_backup|
        puts "   - #{File.basename(old_backup)}"
        FileUtils.rm_rf(old_backup)
      end
    end

    # Show summary
    final_count = Dir.glob("./site_backups/20*").length
    backup_size = `du -sh #{backup_dir}`.split.first rescue "unknown"
    total_size = `du -sh ./site_backups`.split.first rescue "unknown"

    puts "\n✅ Backup complete!"
    puts "📊 Backup size: #{backup_size}"
    puts "📂 Total backups: #{final_count}/15 (#{total_size})"
    puts "🔗 Latest: site_backups/latest"
  end

  desc "Push specific folders to production (e.g., rake site:push_folders[posts,theme])"
  task :push_folders, [:folders] do |t, args|
    unless args[:folders]
      puts "❌ Usage: rake site:push_folders[posts,theme]"
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

  desc "Restore production from backup (interactive or direct: rake site:rollback_site[latest])"
  task :rollback, [:backup_name] do |t, args|
    backup_name = args[:backup_name]

    # --- Direct Mode (with argument) ---
    if backup_name
      # Resolve 'latest' symlink
      if backup_name == 'latest'
        unless File.symlink?("./site_backups/latest")
          puts "❌ No 'latest' symlink found"
          exit 1
        end
        backup_name = File.readlink("./site_backups/latest")
        puts "🔗 Resolved 'latest' → #{backup_name}"
      end

      backup_path = "./site_backups/#{backup_name}"

      unless Dir.exist?(backup_path)
        puts "❌ Backup not found: #{backup_name}"
        puts "\nAvailable backups:"
        Dir.glob("./site_backups/20*").sort.reverse.each { |b| puts "  - #{File.basename(b)}" }
        exit 1
      end

      puts "\n⚠️  This will OVERWRITE production with: #{backup_name}"
      print "Type 'yes' to confirm: "
      unless STDIN.gets.chomp == 'yes'
        puts "❌ Rollback cancelled"
        exit 0
      end

      machine = machine_id
      puts "\n⏮️  Restoring #{backup_name} to production..."
      system("rsync -avP --delete -e ./bin/fly-rsync #{backup_path}/ #{machine}:/data/site/")
      puts "✅ Rollback complete!"
      exit 0
    end

    # --- Interactive Mode (no argument) ---
    backups = Dir.glob("./site_backups/20*").sort.reverse

    if backups.empty?
      puts "❌ No backups found in site_backups/"
      exit 1
    end

    puts "📂 Available backups:"
    backups.each_with_index do |backup, i|
      timestamp = File.basename(backup)
      size = `du -sh #{backup}`.split.first rescue "?"

      # Show 'latest' indicator
      is_latest = File.symlink?("./site_backups/latest") &&
                  File.readlink("./site_backups/latest") == timestamp
      latest_marker = is_latest ? " ← latest" : ""

      puts "  #{i + 1}) #{timestamp} (#{size})#{latest_marker}"
    end

    print "\nChoose backup to restore (1-#{backups.length}) or 'q' to quit: "
    choice = STDIN.gets.chomp

    exit 0 if choice.downcase == 'q'

    choice = choice.to_i
    unless choice.between?(1, backups.length)
      puts "❌ Invalid choice"
      exit 1
    end

    backup_path = backups[choice - 1]
    timestamp = File.basename(backup_path)

    puts "\n⚠️  This will OVERWRITE production with: #{timestamp}"
    print "Type 'yes' to confirm: "

    unless STDIN.gets.chomp == 'yes'
      puts "❌ Rollback cancelled"
      exit 0
    end

    machine = machine_id
    puts "\n⏮️  Restoring #{timestamp} to production..."
    system("rsync -avP --delete -e ./bin/fly-rsync #{backup_path}/ #{machine}:/data/site/")
    puts "✅ Rollback complete!"
  end
end
