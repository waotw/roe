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

  # Database Protection: rsync exclude patterns
  # NEVER push local production DB copies to production
  # NEVER pull production DB into development folder
  PUSH_EXCLUDES = [
    '--exclude=db/production/',           # Never overwrite production DBs
    '--exclude=db/development/.gitkeep'   # Don't delete development .gitkeep
  ].freeze

  PULL_EXCLUDES = [
    '--exclude=db/development/',          # Never overwrite development DBs
    '--exclude=db/production/.gitkeep'    # Don't delete production .gitkeep
  ].freeze

  desc "Push site folder to production (protects production databases)"
  task :push do
    machine = machine_id
    puts "📤 Pushing site to #{app_name} (#{machine})..."
    puts "⚠️  This will OVERWRITE content on production!"
    puts "ℹ️  Database protection: site/db/production/ will NOT be overwritten"
    print "Type 'yes' to confirm: "

    confirmation = STDIN.gets.chomp
    unless confirmation == 'yes'
      puts "❌ Aborted"
      exit 0
    end

    # Build rsync command with excludes to protect production DB
    rsync_cmd = "rsync -rltzPi #{PUSH_EXCLUDES.join(' ')} -e ./bin/fly-rsync ./site/ #{machine}:/data/site/"
    system(rsync_cmd)
    puts "✅ Push complete!"
  end

  desc "Pull production database to local site/db/production/"
  task :pull_db do
    machine = machine_id
    puts "📥 Pulling production databases..."

    FileUtils.mkdir_p("./site/db/production")
    system("rsync -avP -e ./bin/fly-rsync #{machine}:/data/site/db/production/ ./site/db/production/")

    # Show what we got
    db_files = Dir.glob("./site/db/production/*.sqlite3")
    if db_files.any?
      puts "✅ Production databases pulled:"
      db_files.each { |f| puts "   - #{File.basename(f)}" }
    else
      puts "⚠️  No database files found in production"
    end
  end

  desc "Push development database to production (DANGEROUS - use with caution)"
  task :push_db do
    machine = machine_id
    puts "⚠️  WARNING: This will OVERWRITE production databases!"
    puts "This should only be used for initial setup or intentional data replacement."
    puts ""
    print "Type 'YES I UNDERSTAND' to confirm: "

    confirmation = STDIN.gets.chomp
    unless confirmation == 'YES I UNDERSTAND'
      puts "❌ Aborted"
      exit 0
    end

    unless Dir.exist?("./site/db/development")
      puts "❌ No development database found at site/db/development/"
      exit 1
    end

    puts "📤 Pushing development databases to production..."
    system("rsync -avP --delete -e ./bin/fly-rsync ./site/db/development/ #{machine}:/data/site/db/production/")
    puts "✅ Database push complete!"
  end

  desc "Backup production site with incremental hard-link snapshots (keeps 15)"
  task :backup do
    machine = machine_id
    timestamp = Time.now.strftime("%Y-%m-%d-%H%M%S")
    backup_root = File.join(RoeSitePaths::ROE_ROOT, 'site_backups')
    backup_dir = File.join(backup_root, timestamp)

    # Find most recent NON-EMPTY backup for hard-linking. Skipping
    # empties matters: if a prior backup ran but rsync failed silently
    # (the bug this task was guarding against), we don't want to point
    # --link-dest at an empty dir — it'd waste a full transfer.
    previous_backups = Dir.glob(File.join(backup_root, "20*")).sort
    previous_backup = previous_backups.reverse.find { |d| Dir.exist?(d) && !Dir.empty?(d) }

    # Build rsync command
    rsync_cmd = "rsync -avP"

    # Add --link-dest if we have a previous backup
    if previous_backup
      # Use absolute path for --link-dest
      link_dest_path = File.expand_path(previous_backup)
      rsync_cmd += " --link-dest='#{link_dest_path}'"
      puts "💾 Creating incremental backup: #{timestamp}"
      puts "   Linking to: #{File.basename(previous_backup)}"
    else
      puts "💾 Creating first full backup: #{timestamp}"
    end

    # Create backup directory
    FileUtils.mkdir_p(backup_dir)

    # Execute rsync - backs up EVERYTHING including both DB folders.
    # IMPORTANT: must check exit status. If rsync fails (e.g. fly-rsync
    # transport breaks) the dir we just made would be empty, and the
    # original task would still update `latest` and rotate-out real
    # backups — that's how all 15 existing backup dirs ended up empty.
    rsync_cmd += " -e ./bin/fly-rsync #{machine}:/data/site/ '#{backup_dir}/'"
    success = system(rsync_cmd)
    exit_status = $?.exitstatus

    unless success
      puts "\n❌ Backup failed (rsync exit status #{exit_status})."
      puts "   Removing empty backup dir: #{timestamp}"
      FileUtils.rm_rf(backup_dir)
      puts "   Leaving previous backups and 'latest' symlink untouched."
      exit 1
    end

    # Belt-and-suspenders: rsync can occasionally exit 0 with nothing
    # transferred under broken transports. An empty dir is never a
    # successful backup, so refuse to advance state.
    if Dir.empty?(backup_dir)
      puts "\n❌ Backup dir is empty after rsync — transport is broken."
      puts "   Removing empty backup dir: #{timestamp}"
      FileUtils.rm_rf(backup_dir)
      puts "   Leaving previous backups and 'latest' symlink untouched."
      exit 1
    end

    # Update 'latest' symlink
    latest_link = File.join(backup_root, 'latest')
    FileUtils.rm_f(latest_link) if File.symlink?(latest_link)
    FileUtils.ln_s(timestamp, latest_link)
    puts "   Updated: site_backups/latest → #{timestamp}"

    # Cleanup: keep only 15 most recent backups
    all_backups = Dir.glob(File.join(backup_root, "20*")).sort
    if all_backups.length > 15
      to_delete = all_backups[0...(all_backups.length - 15)]
      puts "\n🗑️  Removing #{to_delete.length} old backup(s):"
      to_delete.each do |old_backup|
        puts "   - #{File.basename(old_backup)}"
        FileUtils.rm_rf(old_backup)
      end
    end

    # Show summary
    final_count = Dir.glob(File.join(backup_root, "20*")).length
    backup_size = `du -sh #{backup_dir}`.split.first rescue "unknown"
    total_size = `du -sh #{backup_root}`.split.first rescue "unknown"

    puts "\n✅ Backup complete!"
    puts "📊 Backup size: #{backup_size}"
    puts "📂 Total backups: #{final_count}/15 (#{total_size})"
    puts "🔗 Latest: site_backups/latest"
  end

  desc "Push specific folders to production (e.g., rake site:push_folders[posts,theme])"
  task :push_folders, [ :folders ] do |t, args|
    unless args[:folders]
      puts "❌ Usage: rake site:push_folders[posts,theme]"
      exit 1
    end

    machine = machine_id
    folders = args[:folders].split(',')

    # Safety check: prevent database folders from being pushed
    db_folders = folders.select { |f| f.strip.match?(/^db(\/|$)/) }
    if db_folders.any?
      puts "❌ Cannot push database folders using this command: #{db_folders.join(', ')}"
      puts "ℹ️  Use 'rake site:push_db' if you need to push development databases to production"
      exit 1
    end

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

  desc "Preview changes between local and production (dry-run)"
  task :preview_changes do
    machine = machine_id
    puts "📋 Previewing changes (dry-run)..."
    puts "ℹ️  Database folders are protected and won't be synced incorrectly"

    puts "\n--- Files that would be pulled FROM production ---"
    puts "(Excludes: development databases)"
    system("rsync -rltzPin --dry-run #{PULL_EXCLUDES.join(' ')} -e ./bin/fly-rsync #{machine}:/data/site/ ./site/")

    puts "\n--- Files that would be pushed TO production ---"
    puts "(Excludes: production databases)"
    system("rsync -rltzPin --dry-run #{PUSH_EXCLUDES.join(' ')} -e ./bin/fly-rsync ./site/ #{machine}:/data/site/")
  end

  desc "Restore production from backup (interactive or direct: rake site:rollback[latest])"
  task :rollback, [ :backup_name ] do |t, args|
    backup_name = args[:backup_name]
    backup_root = File.join(RoeSitePaths::ROE_ROOT, 'site_backups')

    # --- Direct Mode (with argument) ---
    if backup_name
      # Resolve 'latest' symlink
      if backup_name == 'latest'
        latest_link = File.join(backup_root, 'latest')
        unless File.symlink?(latest_link)
          puts "❌ No 'latest' symlink found"
          exit 1
        end
        backup_name = File.readlink(latest_link)
        puts "🔗 Resolved 'latest' → #{backup_name}"
      end

      backup_path = File.join(backup_root, backup_name)

      unless Dir.exist?(backup_path)
        puts "❌ Backup not found: #{backup_name}"
        puts "\nAvailable backups:"
        Dir.glob(File.join(backup_root, "20*")).sort.reverse.each { |b| puts "  - #{File.basename(b)}" }
        exit 1
      end

      puts "\n⚠️  This will OVERWRITE production with: #{backup_name}"
      puts "This includes content AND production databases from the backup."
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
    backups = Dir.glob(File.join(backup_root, "20*")).sort.reverse

    if backups.empty?
      puts "❌ No backups found in site_backups/"
      exit 1
    end

    puts "📂 Available backups:"
    backups.each_with_index do |backup, i|
      timestamp = File.basename(backup)
      size = `du -sh #{backup}`.split.first rescue "?"

      # Show 'latest' indicator
      latest_link = File.join(backup_root, 'latest')
      is_latest = File.symlink?(latest_link) &&
                  File.readlink(latest_link) == timestamp
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
    puts "This includes content AND production databases from the backup."
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

  desc "Show database locations and status"
  task :db_status do
    puts "📊 Database Status\n\n"

    puts "Development (site/db/development/):"
    dev_dbs = Dir.glob("./site/db/development/*.sqlite3")
    if dev_dbs.any?
      dev_dbs.each do |db|
        size = File.size(db) / 1024.0 / 1024.0
        mtime = File.mtime(db).strftime("%Y-%m-%d %H:%M")
        puts "  ✓ #{File.basename(db)} (#{size.round(2)} MB, modified: #{mtime})"
      end
    else
      puts "  ⚠️  No databases found"
    end

    puts "\nProduction Copy (site/db/production/):"
    prod_dbs = Dir.glob("./site/db/production/*.sqlite3")
    if prod_dbs.any?
      prod_dbs.each do |db|
        size = File.size(db) / 1024.0 / 1024.0
        mtime = File.mtime(db).strftime("%Y-%m-%d %H:%M")
        puts "  ✓ #{File.basename(db)} (#{size.round(2)} MB, modified: #{mtime})"
      end
    else
      puts "  ⚠️  No databases found (run 'rake site:pull_db' to download)"
    end

    puts "\n💡 Tips:"
    puts "  - Run 'rake site:pull_db' to sync production databases locally"
    puts "  - Development databases are pushed to production during deploys"
    puts "  - Use 'rake site:push_db' (CAREFULLY) to overwrite production databases"
  end
end
