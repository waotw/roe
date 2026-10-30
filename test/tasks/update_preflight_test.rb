require "test_helper"
require "rake"

# bin/rails update:preflight checks that the updater's past bug fixes are
# still in place. Those checks look at the code, so moving or rewording the
# code turned them red while nothing was wrong — five went unnoticed until
# someone ran it by hand. Run the parts that need no network here, so the
# next move breaks a test instead.
class UpdatePreflightTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("update:preflight")
    @checker = UpdatePreflightChecker.new
  end

  def run_checks(*names)
    out, = capture_io { names.each { |name| @checker.public_send(name) } }
    out
  end

  test "every bug fix the preflight looks for is found in the current code" do
    out = run_checks(:check_bug_fixes_present, :check_root_sync_sources)

    assert_empty @checker.failures, out
  end

  test "no staging/ folder passes — it only exists while an update runs" do
    Dir.mktmpdir do |root|
      @checker.instance_variable_set(:@staging_path, File.join(root, "staging"))
      run_checks(:check_staging)
      assert_empty @checker.failures

      FileUtils.mkdir_p(File.join(root, "staging"))
      run_checks(:check_staging)
      assert_empty @checker.failures, "an empty staging/ is accepted too"

      File.write(File.join(root, "staging", "leftover"), "x")
      out = run_checks(:check_staging)
      assert_equal 1, @checker.failures.size, "leftover content blocks an update, so it fails"
      assert_includes out, "leftover content"
    end
  end

  test "a source check accepts either quote style" do
    out = run_checks(:check_bug_fixes_present)

    assert_includes out, "✓ Bug 1 (SITE_PATH ENV override)"
    refute_includes out, "✗"
  end

  test "a fix missing from the code is still reported" do
    @checker.stubs(:source).returns("")
    out = run_checks(:check_bug_fixes_present)

    assert_includes @checker.failures, "Bug 1 (SITE_PATH ENV override)"
    assert_includes @checker.failures, "Bug 4 (writes VERSION to root)"
    assert_includes out, "✗ Bug 2 (migrations tested from staging)"
  end
end
