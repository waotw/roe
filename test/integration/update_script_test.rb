require "test_helper"
require "open3"

# bin/update is the new release's own update script (see
# docs/agents/updater-handoff.md). These run it in a throwaway Roe folder,
# with a stand-in `mise`, for the parts that don't need a real release:
# where it may run from, the protocol check, asking before installing Ruby,
# and cancelling.
class UpdateScriptTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("update-script")
    @dir = File.join(@root, "backups", "updates", "20261126_100000-1")
    FileUtils.mkdir_p(@dir)
    FileUtils.cp(Rails.root.join("bin", "update"), File.join(@dir, "update.sh"))

    FileUtils.mkdir_p(File.join(@root, "staging"))
    File.write(File.join(@root, "staging", ".ruby-version"), "9.9.9\n")
    FileUtils.mkdir_p(File.join(@root, "current"))

    # A mise that has no Ruby installed.
    @bin = File.join(@root, "fakebin")
    FileUtils.mkdir_p(@bin)
    File.write(File.join(@bin, "mise"), "#!/bin/sh\nexit 1\n")
    File.chmod(0o755, File.join(@bin, "mise"))
  end

  teardown { FileUtils.rm_rf(@root) }

  def run_script(*args, script: File.join(@dir, "update.sh"))
    env = { "HOME" => @root, "PATH" => "#{@bin}:/usr/bin:/bin" }
    _out, err, status = Open3.capture3(env, "bash", script, *args, stdin_data: "")
    [ status.exitstatus, err ]
  end

  def contract_args(protocol: "1")
    [ "--protocol", protocol, "--root", @root, "--update-id", "1",
      "--from", "0.5.0", "--to", "0.5.1", "--db-backup", "20261126_095959" ]
  end

  def status_json = JSON.parse(File.read(File.join(@dir, "status.json")))

  test "it won't run from inside a release, only from an update folder" do
    code, err = run_script(*contract_args, script: Rails.root.join("bin", "update").to_s)
    assert_equal 2, code
    assert_match(/backups\/updates/, err)
  end

  test "an unknown protocol fails clearly instead of guessing" do
    code, = run_script(*contract_args(protocol: "99"))
    assert_equal 2, code
    assert_equal "failed", status_json["state"]
    assert_match(/protocol 99/, status_json["message"])
  end

  test "a missing Ruby is asked about before anything is installed" do
    code, = run_script(*contract_args)

    assert_equal 10, code
    data = status_json
    assert_equal "waiting", data["state"]
    assert_equal "install-ruby-9.9.9", data["question"]["key"]
    assert_equal "Ruby 9.9.9 required", data["question"]["title"]
    assert_equal "INSTALL & CONTINUE", data["question"]["confirm"]
    assert_equal "20261126_095959", data["db_backup"]
    assert Dir.exist?(File.join(@root, "staging")), "nothing is touched while waiting"
    assert_match(/Waiting for the go-ahead/, File.read(File.join(@dir, "log.txt")))
  end

  test "cancelling at the question removes the download and marks the update cancelled" do
    run_script(*contract_args)
    code, = run_script(*contract_args, "--cancel")

    assert_equal 0, code
    assert_equal "rolled_back", status_json["state"]
    assert_equal true, status_json["cancelled"]
    refute Dir.exist?(File.join(@root, "staging"))
    assert Dir.exist?(File.join(@root, "current")), "the installed version is untouched"
  end

  test "a person can resume with no arguments; the first run saved them" do
    run_script(*contract_args)
    code, = run_script("--resume")

    assert_equal 10, code, "still waiting for the Ruby go-ahead"
    assert_equal "waiting", status_json["state"]
  end
end
