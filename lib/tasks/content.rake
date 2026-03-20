namespace :content do
  SYNC_PATHS = {
    'site/media' => '/app/site/media',
    'site/system/assets' => '/app/site/system/assets'
  }

  def app_name
    ENV['FLY_APP_NAME'] || `fly status --json 2>/dev/null | jq -r '.Name'`.strip
  end

  desc "Upload local media and assets to production (only new files)"
  task :push_media do
    puts "📤 Syncing to #{app_name}..."

    SYNC_PATHS.each do |local_path, remote_path|
      puts "\n📁 Syncing #{local_path}..."
      files = Dir.glob("#{local_path}/**/*").select { |f| File.file?(f) }

      if files.empty?
        puts "  ⏭️  No files to sync"
        next
      end

      # Build SFTP batch commands
      sftp_commands = []
      files.each do |local_file|
        relative = local_file.sub("#{local_path}/", "")
        remote_file = "#{remote_path}/#{relative}"
        remote_dir = File.dirname(remote_file)

        # Check if file exists remotely
        exists = `fly ssh console -a #{app_name} -C 'test -f #{remote_file} && echo 1 || echo 0'`.strip == "1"

        if exists
          puts "  ⏭️  #{relative} (exists)"
        else
          puts "  📤 #{relative}"
          sftp_commands << "mkdir -p #{remote_dir}" unless sftp_commands.include?("mkdir -p #{remote_dir}")
          sftp_commands << "put #{local_file} #{remote_file}"
        end
      end

      # Execute SFTP commands
      if sftp_commands.any?
        File.open("/tmp/sftp_batch", "w") { |f| f.puts sftp_commands }
        system("fly ssh sftp shell -a #{app_name} < /tmp/sftp_batch")
        File.delete("/tmp/sftp_batch")
      end
    end

    puts "\n✅ Sync complete!"
  end

  desc "Download production media and assets to local (only new files)"
  task :pull_media do
    puts "📥 Pulling from #{app_name}..."

    SYNC_PATHS.each do |local_path, remote_path|
      puts "\n📁 Pulling #{remote_path}..."

      # Get list of remote files
      remote_files = `fly ssh console -a #{app_name} -C 'find #{remote_path} -type f 2>/dev/null'`.split("\n")

      if remote_files.empty?
        puts "  ⏭️  No files found remotely"
        next
      end

      sftp_commands = []
      remote_files.each do |remote_file|
        relative = remote_file.sub("#{remote_path}/", "")
        local_file = "#{local_path}/#{relative}"

        if File.exist?(local_file)
          puts "  ⏭️  #{relative} (exists)"
        else
          puts "  📥 #{relative}"
          FileUtils.mkdir_p(File.dirname(local_file))
          sftp_commands << "get #{remote_file} #{local_file}"
        end
      end

      # Execute SFTP commands
      if sftp_commands.any?
        File.open("/tmp/sftp_batch", "w") { |f| f.puts sftp_commands }
        system("fly ssh sftp shell -a #{app_name} < /tmp/sftp_batch")
        File.delete("/tmp/sftp_batch")
      end
    end

    puts "\n✅ Pull complete!"
  end

  desc "Show differences between local and production media"
  task :diff_media do
    puts "🔍 Comparing local and production media...\n"

    SYNC_PATHS.each do |local_path, remote_path|
      puts "\n📁 #{local_path}"

      local_files = Dir.glob("#{local_path}/**/*")
        .select { |f| File.file?(f) }
        .map { |f| f.sub("#{local_path}/", "") }
        .sort

      remote_files = `fly ssh console -a #{app_name} -C 'find #{remote_path} -type f 2>/dev/null'`
        .split("\n")
        .map { |f| f.sub("#{remote_path}/", "") }
        .sort

      only_local = local_files - remote_files
      only_remote = remote_files - local_files
      in_sync = local_files & remote_files

      if only_local.any?
        puts "  📍 Only local (#{only_local.count}):"
        only_local.first(5).each { |f| puts "    #{f}" }
        puts "    ... and #{only_local.count - 5} more" if only_local.count > 5
      end

      if only_remote.any?
        puts "  ☁️  Only remote (#{only_remote.count}):"
        only_remote.first(5).each { |f| puts "    #{f}" }
        puts "    ... and #{only_remote.count - 5} more" if only_remote.count > 5
      end

      puts "  ✅ In sync: #{in_sync.count} files"
    end

    puts "\n"
  end

  desc "Backup production media to local backups directory"
  task :backup do
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_dir = "backups/#{timestamp}"
    FileUtils.mkdir_p(backup_dir)

    puts "💾 Creating backup: #{backup_dir}"

    SYNC_PATHS.each do |local_path, remote_path|
      puts "\n📁 Backing up #{remote_path}..."

      remote_files = `fly ssh console -a #{app_name} -C 'find #{remote_path} -type f 2>/dev/null'`.split("\n")

      next if remote_files.empty?

      sftp_commands = remote_files.map do |remote_file|
        relative = remote_file.sub("#{remote_path}/", "")
        local_file = "#{backup_dir}/#{File.basename(local_path)}/#{relative}"
        FileUtils.mkdir_p(File.dirname(local_file))
        "get #{remote_file} #{local_file}"
      end

      File.open("/tmp/sftp_batch", "w") { |f| f.puts sftp_commands }
      system("fly ssh sftp shell -a #{app_name} < /tmp/sftp_batch")
      File.delete("/tmp/sftp_batch")

      puts "  ✅ #{remote_files.count} files"
    end

    puts "\n✅ Backup complete: #{backup_dir}"
  end
end

# namespace :content do
#   desc "Sync all content from markdown files"
#   task sync: :environment do
#     ContentSync.sync_all
#   end
# end
