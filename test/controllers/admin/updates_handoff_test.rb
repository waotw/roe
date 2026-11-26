require "test_helper"

# The Updates page while the new release runs the update itself
# (RoeUpdater::Handoff): its question, its help, and its answers.
class Admin::UpdatesHandoffTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    RoeUpdater::VersionChecker.stubs(:dev_install?).returns(false)
    RoeUpdater::VersionChecker.stubs(:check_for_updates).returns(nil)
    @tmp = Dir.mktmpdir("updates-handoff")
    RoeUpdater::Handoff.stubs(:updates_dir).returns(@tmp)
    @status = UpdateStatus.create!(status: "in_progress", from_version: "0.5.0", to_version: "0.5.1")
    @dir = File.join(@tmp, "20261126_100000-#{@status.id}")
    FileUtils.mkdir_p(@dir)
  end

  teardown { FileUtils.rm_rf(@tmp) }

  def write_status(data)
    File.write(File.join(@dir, "status.json"), JSON.generate({ "protocol" => 1, "updated_at" => Time.now.utc.iso8601 }.merge(data)))
  end

  test "the page shows the script's question with its own buttons" do
    write_status("state" => "waiting", "step" => "Ruby 4.0.11 required",
                 "question" => { "key" => "install-ruby-4.0.11", "title" => "Ruby 4.0.11 required",
                                 "text" => "Install it with `mise`?", "confirm" => "INSTALL & CONTINUE", "cancel" => "CANCEL" })

    get admin_updates_path

    assert_response :success
    assert_select "[data-test=update-question] h2", "Ruby 4.0.11 required"
    assert_select "[data-test=update-question] code", "mise"
    assert_select "[data-test=update-question-confirm]"
    assert_equal "awaiting_input", @status.reload.status
  end

  test "answering carries on through the script" do
    write_status("state" => "waiting", "question" => { "key" => "install-ruby-4.0.11", "title" => "Ruby" })
    @status.update!(status: "awaiting_input")
    RoeUpdater::Handoff.expects(:answer).with(@status, confirm: true).returns(true)

    post admin_answer_update_path, params: { confirm: "1" }

    assert_redirected_to admin_updates_path
  end

  test "the status poll carries the script's help and the slow notice" do
    File.write(File.join(@dir, "pid"), Process.pid.to_s)
    File.write(File.join(@dir, "status.json"), JSON.generate(
      "protocol" => 1, "state" => "running", "step" => "Installing gems (3 so far)", "percent" => 45,
      "help" => "Run `roe restart` if it stays here.", "updated_at" => 11.minutes.ago.utc.iso8601
    ))

    get admin_update_status_path, as: :json

    data = response.parsed_body
    assert_equal "in_progress", data["status"]
    assert_equal "Installing gems (3 so far)", data["step"]
    assert data["slow"]
    assert_includes data["help_html"], "<code>roe restart</code>"
  end

  test "an update that stopped partway shows the commands to resume or roll back" do
    pid = Process.spawn("true")
    Process.wait(pid)
    File.write(File.join(@dir, "pid"), pid.to_s)
    File.write(File.join(@dir, "status.json"), JSON.generate(
      "protocol" => 1, "state" => "running", "step" => "Installing gems", "percent" => 45,
      "updated_at" => 5.minutes.ago.utc.iso8601
    ))

    get admin_updates_path

    assert_select "[data-test=update-failed-handoff]" do
      assert_select "code", /update\.sh --resume/
      assert_select "code", /update\.sh --rollback/
    end
  end
end
