require "test_helper"

module RoeUpdater
  # The hard safety net: the updater must refuse to clone a release over a
  # developer checkout of Roe (HEAD on a named branch), on EVERY entry
  # point — not just the web button. Regression cover for the incident
  # where "Test nightly" wiped an uncommitted working tree.
  class UpdateOrchestratorDevGuardTest < ActiveSupport::TestCase
    def setup
      @status = UpdateStatus.create!(
        status: "in_progress", from_version: "1.0.0", to_version: "9.9.9",
        current_step: "queued", progress_percent: 0
      )
      UpdateOrchestrator.instance_variable_set(:@status, @status)
    end

    # Swap VersionChecker.dev_install? for a fixed value, restoring after.
    def with_dev_install(value)
      sc = VersionChecker.singleton_class
      sc.send(:alias_method, :__orig_di, :dev_install?)
      sc.send(:define_method, :dev_install?) { value }
      yield
    ensure
      sc.send(:alias_method, :dev_install?, :__orig_di)
      sc.send(:remove_method, :__orig_di)
    end

    test "a user install (detached release tag) is NOT refused" do
      with_dev_install(false) do
        refute UpdateOrchestrator.send(:refuse_on_dev_checkout!)
      end
    end

    test "a dev checkout IS refused and the update is marked failed" do
      with_dev_install(true) do
        assert UpdateOrchestrator.send(:refuse_on_dev_checkout!)
      end
      @status.reload
      assert_equal "failed", @status.status
      assert_equal "Refused — development checkout", @status.current_step
      assert_match(/development checkout/i, @status.error_message)
    end

    test "ROE_ALLOW_DEV_UPDATE=1 overrides the refusal (maintainer escape hatch)" do
      with_dev_install(true) do
        ENV["ROE_ALLOW_DEV_UPDATE"] = "1"
        refute UpdateOrchestrator.send(:refuse_on_dev_checkout!)
      ensure
        ENV.delete("ROE_ALLOW_DEV_UPDATE")
      end
    end

    test "start_update bails on a dev checkout before any destructive step" do
      with_dev_install(true) do
        UpdateOrchestrator.start_update("9.9.9", @status)
      end
      @status.reload
      assert_equal "failed", @status.status
      assert_equal "Refused — development checkout", @status.current_step
    end
  end
end
