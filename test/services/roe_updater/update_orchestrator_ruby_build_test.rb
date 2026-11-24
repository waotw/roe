require "test_helper"

# mise's ready-made macOS Rubies are built on the newest macOS, and their
# headers need <stdckdint.h>, which macOS 14's build tools haven't got. On
# such a Mac the updater builds Ruby from source, and treats an installed
# ready-made Ruby as missing, so the update can't fail later at
# installing_gems.
module RoeUpdater
  class UpdateOrchestratorRubyBuildTest < ActiveSupport::TestCase
    setup do
      @dir = Dir.mktmpdir("ruby-install")
      FileUtils.mkdir_p(File.join(@dir, "include", "ruby-4.0.0", "arm64-darwin25", "ruby"))
      @config = File.join(@dir, "include", "ruby-4.0.0", "arm64-darwin25", "ruby", "config.h")
    end

    teardown { FileUtils.rm_rf(@dir) }

    def orchestrator = UpdateOrchestrator

    test "on a Mac whose compiler lacks <stdckdint.h>, Ruby is built from source" do
      orchestrator.stubs(:system).with("command -v cc > /dev/null 2>&1").returns(true)
      orchestrator.stubs(:system).with(regexp_matches(/stdckdint/)).returns(false)

      assert_equal RUBY_PLATFORM.include?("darwin"), orchestrator.send(:ruby_from_source?)
    end

    test "with the header, or no compiler at all, the ready-made Ruby is used" do
      orchestrator.stubs(:system).with("command -v cc > /dev/null 2>&1").returns(true)
      orchestrator.stubs(:system).with(regexp_matches(/stdckdint/)).returns(true)
      refute orchestrator.send(:ruby_from_source?)

      orchestrator.stubs(:system).with("command -v cc > /dev/null 2>&1").returns(false)
      refute orchestrator.send(:ruby_from_source?)
    end

    test "an installed Ruby that needs the missing header counts as unusable" do
      orchestrator.stubs(:ruby_from_source?).returns(true)
      orchestrator.stubs(:`).returns("#{@dir}\n")

      File.write(@config, "#define HAVE_STDCKDINT_H 1\n")
      assert orchestrator.send(:ready_made_ruby_unusable?, "mise", "4.0.10")

      File.write(@config, "/* #undef HAVE_STDCKDINT_H */\n")
      refute orchestrator.send(:ready_made_ruby_unusable?, "mise", "4.0.10")
    end

    test "nothing counts as unusable on a Mac that has the header" do
      orchestrator.stubs(:ruby_from_source?).returns(false)
      File.write(@config, "#define HAVE_STDCKDINT_H 1\n")

      refute orchestrator.send(:ready_made_ruby_unusable?, "mise", "4.0.10")
    end
  end
end
