require "test_helper"

# The updater hands an update to the new release's own bin/update, then reads
# its status.json back into the UpdateStatus record. These tests pin the
# contract (docs/agents/updater-handoff.md): what is passed, and how each
# state the script writes shows on the Updates page.
module RoeUpdater
  class HandoffTest < ActiveSupport::TestCase
    setup do
      @tmp = Dir.mktmpdir("handoff")
      @updates = File.join(@tmp, "backups", "updates")
      Handoff.stubs(:updates_dir).returns(@updates)
      @status = UpdateStatus.create!(status: "in_progress", from_version: "0.5.0", to_version: "0.5.1")
    end

    teardown { FileUtils.rm_rf(@tmp) }

    def update_dir
      dir = File.join(@updates, "20261126_100000-#{@status.id}")
      FileUtils.mkdir_p(dir)
      dir
    end

    def write_status(dir, data, updated_at: Time.now.utc)
      File.write(File.join(dir, "status.json"), JSON.generate({ "protocol" => 1 }.merge(data).merge("updated_at" => updated_at.iso8601)))
    end

    def dead_pid
      pid = Process.spawn("true")
      Process.wait(pid)
      pid
    end

    test "a release counts as installing itself only when it ships bin/update" do
      staging = File.join(@tmp, "staging")
      FileUtils.mkdir_p(File.join(staging, "bin"))
      refute Handoff.available?(staging)

      File.write(File.join(staging, "bin", "update"), "#!/bin/bash\n")
      assert Handoff.available?(staging)
    end

    test "start copies the script, passes the contract's arguments, and runs it outside this process" do
      staging = File.join(@tmp, "staging")
      FileUtils.mkdir_p(File.join(staging, "bin"))
      File.write(File.join(staging, "bin", "update"), <<~SH)
        #!/usr/bin/env bash
        ps -o ppid= -p $$ | tr -d ' ' > "$(dirname "$0")/parent-seen"
        printf '%s\\n' "$@" > "$(dirname "$0")/args-seen"
      SH

      dir = Handoff.start(@status, db_backup: "20261126_095959", staging: staging)

      assert File.executable?(File.join(dir, "update.sh"))
      assert_match(/-#{@status.id}\z/, dir)
      seen = File.join(dir, "args-seen")
      Timeout.timeout(10) { sleep 0.1 until File.exist?(seen) && File.size(seen).positive? }
      args = File.read(seen).split("\n")
      assert_equal "1", args[args.index("--protocol") + 1]
      assert_equal @status.id.to_s, args[args.index("--update-id") + 1]
      assert_equal "0.5.0", args[args.index("--from") + 1]
      assert_equal "0.5.1", args[args.index("--to") + 1]
      assert_equal "20261126_095959", args[args.index("--db-backup") + 1]
      assert File.exist?(File.join(dir, "pid"))
      refute_equal Process.pid.to_s, File.read(File.join(dir, "parent-seen")).strip,
                   "the script must not be a child of Roe's own process, or it can't stop that process"
      assert_equal "running", Handoff.read_status(dir)["state"]
    end

    test "a running update shows its step, progress and log" do
      dir = update_dir
      File.write(File.join(dir, "pid"), Process.pid.to_s)
      File.write(File.join(dir, "log.txt"), "first line\nInstalling gems\n")
      write_status(dir, { "state" => "running", "step" => "Installing gems (12 so far)", "percent" => 45 })

      info = Handoff.sync(@status)

      @status.reload
      assert_equal "in_progress", @status.status
      assert_equal "Installing gems (12 so far)", @status.current_step
      assert_equal 45, @status.progress_percent
      assert_includes @status.log, "Installing gems"
      refute info.slow
      refute info.interrupted
    end

    test "a question from the script pauses the update and is shown as written" do
      dir = update_dir
      File.write(File.join(dir, "pid"), dead_pid.to_s)
      question = { "key" => "install-ruby-4.0.11", "title" => "Ruby 4.0.11 required", "text" => "Install it?",
                   "confirm" => "INSTALL & CONTINUE", "cancel" => "CANCEL" }
      write_status(dir, { "state" => "waiting", "step" => "Ruby 4.0.11 required", "percent" => 35, "question" => question })

      info = Handoff.sync(@status)

      assert_equal "awaiting_input", @status.reload.status
      assert_equal "install-ruby-4.0.11", info.question["key"]
      refute info.interrupted, "a script waiting for an answer has exited on purpose"
    end

    test "a finished update is completed at the time the script gives" do
      dir = update_dir
      write_status(dir, { "state" => "done", "step" => "Update completed successfully", "percent" => 100,
                        "completed_at" => "2026-11-26T10:05:00Z", "restarted" => true })

      Handoff.sync(@status)

      @status.reload
      assert_equal "completed", @status.status
      assert_equal Time.utc(2026, 11, 26, 10, 5, 0), @status.completed_at
    end

    test "a cancelled update is dropped, so the page offers the update again" do
      dir = update_dir
      write_status(dir, { "state" => "rolled_back", "message" => "Update cancelled.", "cancelled" => true })

      assert_nil Handoff.sync(@status)
      assert_not UpdateStatus.exists?(@status.id)
    end

    test "a rolled-back update keeps its reason" do
      dir = update_dir
      write_status(dir, { "state" => "rolled_back", "message" => "The gems couldn't be installed.", "help" => "Check the connection." })

      info = Handoff.sync(@status)

      assert_equal "rolled_back", @status.reload.status
      assert_equal "The gems couldn't be installed.", @status.error_message
      assert_equal "Check the connection.", info.help
    end

    test "an update whose process has gone partway is shown as stopped, with commands to resume or roll back" do
      dir = update_dir
      File.write(File.join(dir, "pid"), dead_pid.to_s)
      write_status(dir, { "state" => "running", "step" => "Installing gems", "percent" => 45 }, updated_at: 5.minutes.ago.utc)

      info = Handoff.sync(@status)

      assert info.interrupted
      assert_equal "failed", @status.reload.status
      assert_includes info.commands[:resume], "update.sh --resume"
      assert_includes info.commands[:rollback], "update.sh --rollback"
    end

    test "an update that is alive but quiet for ten minutes is shown as slow" do
      dir = update_dir
      File.write(File.join(dir, "pid"), Process.pid.to_s)
      write_status(dir, { "state" => "running", "step" => "Installing gems (80 so far)", "percent" => 45 }, updated_at: 11.minutes.ago.utc)

      info = Handoff.sync(@status)

      assert info.slow
      assert_equal "in_progress", @status.reload.status
    end

    test "an update run in the old way has no folder and is left alone" do
      assert_nil Handoff.sync(@status)
      assert_equal "in_progress", @status.reload.status
    end

    test "only the five most recent update folders are kept" do
      7.times { |i| FileUtils.mkdir_p(File.join(@updates, "2026112#{i}_100000-#{900 + i}")) }
      Handoff.send(:prune)
      assert_equal 5, Dir.children(@updates).size
      refute Dir.exist?(File.join(@updates, "20261120_100000-900"))
    end
  end
end
