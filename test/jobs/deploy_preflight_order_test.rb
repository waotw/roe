require "test_helper"

# A Fly deploy with a signed-out session has to stop with "You're not signed
# in to Fly" and the steps to fix it. It used to end with the watchdog's
# generic "Roe stopped before this deploy finished": the secrets sync ran
# first, asked Fly for its secret list, and raised — before the sign-in check
# was reached, and without writing anything the page could show.
class DeployPreflightOrderTest < ActiveSupport::TestCase
  KEY = PerformDeployJob::STATUS_CACHE_KEY

  setup do
    Rails.cache.write(KEY, { state: :running, target: "fly", version_tag: "100",
                             started_at: Time.current, log: "" })
  end
  teardown { Rails.cache.delete(KEY) }

  def signed_out
    DeployPreflight.new.send(:fly_signed_out_issue)
  end

  test "a signed-out Fly deploy stops at the sign-in check, before touching git or Fly" do
    DeployPreflight.any_instance.stubs(:fly_auth_state).returns(:signed_out)
    DeployPreflight.any_instance.stubs(:fly_cli?).returns(true)
    job = PerformDeployJob.new
    job.expects(:prepare_version_file).never
    job.expects(:auto_commit).never
    FlySecretsSync.expects(:run).never
    job.expects(:run_with_streaming).never

    job.perform(target: "fly", version_tag: "100")

    status = Rails.cache.read(KEY)
    assert_equal :failed, status[:state]
    assert_includes status[:error], "You're not signed in to Fly"
    assert_equal [ "fly_signed_out" ], status[:preflight].map { |b| b[:key] },
                 "the page renders the sign-in steps from admin/shared/_fly_signed_out"
  end

  test "a failure while preparing the deploy is shown on the page, not left for the watchdog" do
    DeployPreflight.any_instance.stubs(:blockers).returns([])
    job = PerformDeployJob.new
    job.stubs(:prepare_version_file)
    job.stubs(:auto_commit)
    FlySecretsSync.stubs(:run).raises(RuntimeError, "Fly authentication isn't set up. Run `fly auth login` from a terminal once, then retry the deploy.")
    job.expects(:run_with_streaming).never

    assert_raises(RuntimeError) { job.perform(target: "fly", version_tag: "100") }

    status = Rails.cache.read(KEY)
    assert_equal :failed, status[:state], "not still :running, which is what the watchdog later reports as abandoned"
    assert_includes status[:error], "fly auth login"
    assert_not DeployWatchdog.new.send(:abandoned?, status), "the watchdog leaves a recorded failure alone"
  end
end
