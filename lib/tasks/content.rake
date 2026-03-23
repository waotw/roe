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
end
