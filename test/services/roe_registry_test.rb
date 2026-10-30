require "test_helper"

class RoeRegistryTest < ActiveSupport::TestCase
  # Point the registry at a throwaway folder so nothing on this machine's
  # real ~/.roe is read or written.
  setup do
    @home = Dir.mktmpdir("roe-registry")
    @installs = File.join(@home, "installs")
    FileUtils.mkdir_p(@installs)
    @original_home = ENV["ROE_HOME"]
    ENV["ROE_HOME"] = @home
  end

  teardown do
    ENV["ROE_HOME"] = @original_home
    FileUtils.rm_rf(@home)
  end

  def register(name, root)
    File.write(File.join(@installs, "#{name}.conf"),
      "NAME=#{name}\nROOT=#{root}\nHOST=#{name}.roe\nPORT=3000\n")
  end

  test "no registry means no entries and no restart command" do
    FileUtils.rm_rf(@installs)
    assert_equal [], RoeRegistry.entries
    assert_nil RoeRegistry.restart_command
    assert_not RoeRegistry.registered?
  end

  test "an unregistered install has no restart command even when others are registered" do
    register("other-site", "/somewhere/else")
    assert_equal 1, RoeRegistry.entries.size
    assert_nil RoeRegistry.restart_command
  end

  test "the only registered site restarts with a bare roe restart" do
    register("this-site", RoeSitePaths::ROE_ROOT.to_s)
    assert RoeRegistry.registered?
    assert_equal "roe restart", RoeRegistry.restart_command
  end

  test "with several registered sites the command names this one" do
    register("this-site", RoeSitePaths::ROE_ROOT.to_s)
    register("other-site", "/somewhere/else")
    assert_equal "roe restart this-site", RoeRegistry.restart_command
  end

  test "a conf missing NAME or ROOT is ignored" do
    File.write(File.join(@installs, "broken.conf"), "HOST=broken.roe\n")
    register("this-site", RoeSitePaths::ROE_ROOT.to_s)
    assert_equal %w[this-site], RoeRegistry.entries.map(&:name)
  end
end
