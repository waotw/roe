require "json"
require "fileutils"
require "shellwords"

module RoeUpdater
  # Hands an update over to the release being installed.
  #
  # An update is carried out by the installed version's code, so a fix to how
  # updates work used to reach users one release late. Instead, once a release
  # is downloaded into staging/, the updater runs that release's own
  # `bin/update` and steps back: the release installs itself.
  #
  # THIS FILE IS FROZEN ONCE SHIPPED. Every install that has it will use it to
  # start every future update, so what it passes to the script and what it
  # reads back (the contract in docs/agents/updater-handoff.md) can grow but
  # never change. Keep the script's steps in bin/update, where they can change
  # with every release.
  class Handoff
    PROTOCOL = 1
    SCRIPT = File.join("bin", "update")
    KEEP = 5

    # A running update whose status.json hasn't moved for this long, while its
    # process is still alive, gets "This is taking longer than usual".
    SLOW_AFTER = 10.minutes
    # A running update whose process has gone, and whose status.json hasn't
    # moved for this long, stopped partway.
    GONE_AFTER = 30.seconds

    STATES = {
      "running"     => "in_progress",
      "waiting"     => "awaiting_input",
      "done"        => "completed",
      "failed"      => "failed",
      "rolled_back" => "rolled_back"
    }.freeze

    # What the page needs beyond the UpdateStatus record.
    Info = Struct.new(:dir, :question, :help, :interrupted, :slow, keyword_init: true) do
      def commands
        script = File.join(dir, "update.sh")
        { resume: "bash #{script.shellescape} --resume", rollback: "bash #{script.shellescape} --rollback" }
      end
    end

    class << self
      # backups/updates/: one folder per update the new version ran itself.
      def updates_dir
        File.join(RoeSitePaths::ROE_ROOT, "backups", "updates")
      end

      # Does the downloaded release ship its own update steps?
      def available?(staging = Downloader::STAGING_PATH)
        File.file?(File.join(staging, SCRIPT))
      end

      # Copy the release's script to this update's own folder, start it outside
      # the server, and return. Everything after this is the script's.
      def start(status, db_backup:, staging: Downloader::STAGING_PATH)
        dir = File.join(updates_dir, "#{Time.now.strftime('%Y%m%d_%H%M%S')}-#{status.id}")
        FileUtils.mkdir_p(dir)
        FileUtils.cp(File.join(staging, SCRIPT), File.join(dir, "update.sh"))
        File.chmod(0o755, File.join(dir, "update.sh"))

        write_status(dir, "protocol" => PROTOCOL, "state" => "running",
                          "step" => "Handing over to Roe #{status.to_version}", "percent" => 32)
        launch(status, dir, db_backup: db_backup)
        prune
        dir
      end

      # The person answered a question the script asked (state "waiting").
      def answer(status, confirm:)
        info = sync(status)
        return false unless info&.question

        write_status(info.dir, read_status(info.dir).merge(
          "state" => "running", "question" => nil, "help" => nil,
          "step" => confirm ? "Continuing…" : "Cancelling…"
        ))
        status.update!(status: "in_progress", current_step: confirm ? "Continuing…" : "Cancelling…")
        extra = confirm ? [ "--confirmed", info.question["key"].to_s ] : [ "--cancel" ]
        launch(status, info.dir, db_backup: read_status(info.dir)["db_backup"], extra: extra)
        true
      end

      # Bring the UpdateStatus record up to date from the script's
      # status.json. Returns nil for an update the script isn't running (an
      # older in-process update), otherwise what the page shows beyond it.
      def sync(status)
        return nil unless status

        dir = dir_for(status)
        return nil unless dir

        data = read_status(dir)
        return nil if data.empty?

        state = data["state"].to_s

        # Cancelled at a question: nothing changed, so the attempt is dropped
        # and the page goes back to offering the update.
        if state == "rolled_back" && data["cancelled"] == true
          status.destroy
          return nil
        end
        updated_at = (Time.iso8601(data["updated_at"].to_s) rescue File.mtime(File.join(dir, "status.json")))
        alive = process_alive?(dir)
        interrupted = state == "running" && !alive && updated_at < GONE_AFTER.ago
        slow = state == "running" && alive && updated_at < SLOW_AFTER.ago

        attrs = {
          status: STATES.fetch(state, status.status),
          current_step: (interrupted ? "The update stopped partway" : data["step"].presence || status.current_step),
          progress_percent: data["percent"] || status.progress_percent,
          error_message: data["message"].presence || (interrupted ? "The update stopped before it finished." : status.error_message),
          log: log_tail(dir).presence || status.log
        }
        attrs[:status] = "failed" if interrupted
        if attrs[:status] == "completed" && status.status != "completed"
          attrs[:completed_at] = (Time.iso8601(data["completed_at"].to_s) rescue Time.current)
          finished!
        end
        status.update!(attrs.select { |key, value| status.public_send(key) != value })

        Info.new(dir: dir, question: (data["question"] if state == "waiting"), help: data["help"].presence,
                 interrupted: interrupted, slow: slow)
      end

      def dir_for(status)
        Dir.glob(File.join(updates_dir, "*-#{status.id}")).max
      end

      def read_status(dir)
        JSON.parse(File.read(File.join(dir, "status.json")))
      rescue StandardError
        {}
      end

      private

      def launch(status, dir, db_backup:, extra: [])
        args = [
          "--protocol", PROTOCOL.to_s,
          "--root", RoeSitePaths::ROE_ROOT,
          "--update-id", status.id.to_s,
          "--from", status.from_version.to_s,
          "--to", status.to_version.to_s,
          "--db-backup", db_backup.to_s
        ] + extra

        # Started through a shell that exits at once, so the script's parent
        # is the system, not this process. It must not count as part of Roe:
        # it stops Roe's server and job processes to restart them, and on
        # macOS `pgrep` never lists a process's own ancestors, so a script
        # started by the job process couldn't find that job process to stop.
        reader, writer = IO.pipe
        shell = Bundler.with_original_env do
          Process.spawn(
            { "ROE_UPDATE_OUTPUT" => File.join(dir, "output.txt") },
            "/bin/sh", "-c", 'bash "$@" < /dev/null >> "$ROE_UPDATE_OUTPUT" 2>&1 & echo $!',
            "sh", File.join(dir, "update.sh"), *args,
            chdir: RoeSitePaths::ROE_ROOT, pgroup: true, in: File::NULL, out: writer, err: File::NULL
          )
        end
        writer.close
        pid = reader.read.to_i
        reader.close
        Process.wait(shell)
        File.write(File.join(dir, "pid"), pid.to_s)
        pid
      end

      def write_status(dir, data)
        path = File.join(dir, "status.json")
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, JSON.pretty_generate(data.merge("updated_at" => Time.now.utc.iso8601)))
        File.rename(tmp, path)
      end

      def process_alive?(dir)
        pid = File.read(File.join(dir, "pid")).to_i
        return false unless pid.positive?

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::ENOENT
        false
      rescue Errno::EPERM
        true
      end

      def log_tail(dir, lines: 400)
        path = File.join(dir, "log.txt")
        return "" unless File.exist?(path)

        File.readlines(path, chomp: true).last(lines).join("\n")
      rescue StandardError
        ""
      end

      # Housekeeping the in-process updater did on completion.
      def finished!
        VersionChecker.clear_cache
        Rails.cache.delete(VersionChecker::UPDATE_AVAILABLE_KEY)
        BackupManager.cleanup_update_backups
      rescue StandardError => e
        Rails.logger.warn "[RoeUpdater] After-update housekeeping failed: #{e.message}"
      end

      def prune
        dirs = Dir.glob(File.join(updates_dir, "*")).select { |d| File.directory?(d) }.sort
        (dirs[0...-KEEP] || []).each { |d| FileUtils.rm_rf(d) }
      end
    end
  end
end
