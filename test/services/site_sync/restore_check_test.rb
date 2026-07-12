require "test_helper"

module SiteSync
  class RestoreCheckTest < ActiveSupport::TestCase
    def setup
      RestoreCheck.clear!
    end

    def teardown
      RestoreCheck.clear!
    end

    test "run_if_pending! is a cheap no-op when no restore is pending" do
      refute RestoreCheck.needed?
      RestoreCheck.run_if_pending!
      refute RestoreCheck.credentials_mismatch?
    end

    test "clears the mismatch flag when encrypted data is readable" do
      RestoreCheck.mark_needed!
      RestoreCheck.flag_mismatch!

      # Test-env integration secrets are blank/readable → probe passes.
      RestoreCheck.run_if_pending!

      refute RestoreCheck.needed?, "needed marker consumed (runs once)"
      refute RestoreCheck.credentials_mismatch?, "mismatch cleared when readable"
    end

    test "flags a mismatch when encrypted data can't be read" do
      RestoreCheck.mark_needed!
      stub_unreadable { RestoreCheck.run_if_pending! }

      refute RestoreCheck.needed?
      assert RestoreCheck.credentials_mismatch?, "mismatch flagged when unreadable"
    end

    test "credentials_mismatch? reflects the marker" do
      refute RestoreCheck.credentials_mismatch?
      RestoreCheck.flag_mismatch!
      assert RestoreCheck.credentials_mismatch?
      RestoreCheck.clear!
      refute RestoreCheck.credentials_mismatch?
    end

    private

    # Force encrypted_data_readable? false without minitest/mock (which trips
    # this project's test-runner arg parsing).
    def stub_unreadable
      sc = RestoreCheck.singleton_class
      sc.send(:alias_method, :__orig_readable, :encrypted_data_readable?)
      sc.send(:define_method, :encrypted_data_readable?) { false }
      yield
    ensure
      sc.send(:alias_method, :encrypted_data_readable?, :__orig_readable)
      sc.send(:remove_method, :__orig_readable)
    end
  end
end
