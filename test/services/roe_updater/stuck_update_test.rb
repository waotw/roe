require "test_helper"

# An in-process update stopped by a restart of Roe leaves its record "in
# progress", which blocks every later update. Once Roe has started on the
# version it was installing, the record is finished.
module RoeUpdater
  class StuckUpdateTest < ActiveSupport::TestCase
    setup do
      @status = UpdateStatus.create!(status: "in_progress", from_version: "0.4.5", to_version: "0.5.0",
                                     current_step: "Installing required gems")
      @status.update_columns(updated_at: 1.hour.ago)
      Handoff.stubs(:dir_for).returns(nil)
      VersionChecker.stubs(:current_version).returns("0.5.0")
      Rails.application.config.stubs(:server_boot_time).returns(10.minutes.ago)
    end

    test "finishes an update Roe has since started on" do
      assert StuckUpdate.finish_if_installed(@status)
      @status.reload
      assert_equal "completed", @status.status
      assert @status.completed_at < 30.minutes.ago, "finished before this server started, so no restart is asked for"
      assert_match(/Marked finished/, @status.log)
    end

    test "leaves it while the installed version is still the old one" do
      VersionChecker.stubs(:current_version).returns("0.4.5")
      refute StuckUpdate.finish_if_installed(@status)
    end

    test "leaves it if Roe hasn't started since it went quiet" do
      Rails.application.config.stubs(:server_boot_time).returns(2.hours.ago)
      refute StuckUpdate.finish_if_installed(@status)
    end

    test "leaves a recent one, which may still be working" do
      @status.update_columns(updated_at: 2.minutes.ago)
      refute StuckUpdate.finish_if_installed(@status)
    end

    test "leaves an update the new version is running itself" do
      Handoff.stubs(:dir_for).returns("/tmp/somewhere")
      refute StuckUpdate.finish_if_installed(@status)
    end
  end
end
