require "test_helper"

class SiteSyncHelperTest < ActionView::TestCase
  test "collapses documentation/roe files into one row" do
    paths = %w[
      documentation/roe/00-intro.md
      documentation/roe/01-guide.md
      documentation/roe/sub/deep.md
      posts/hello.md
    ]
    rows = collapse_sync_paths(paths)
    assert_equal 2, rows.size
    assert_includes rows, "posts/hello.md"
    assert(rows.any? { |r| r == "Roe documentation — 3 files changed" }, "expected a grouped docs row, got #{rows.inspect}")
  end

  test "the exact prefix path itself collapses" do
    rows = collapse_sync_paths(%w[documentation/roe])
    assert_equal [ "Roe documentation — 1 file changed" ], rows
  end

  Cfg = Struct.new(:peer_deploy_target, :peer_rails_subdir, :peer_folder_name)

  test "restart command: kamal from the rails subdir" do
    assert_equal "cd current && kamal app boot", restore_restart_command(Cfg.new("kamal", "current", "roe"))
  end

  test "restart command: fly from the rails subdir" do
    assert_equal "cd current && fly deploy", restore_restart_command(Cfg.new("fly", "current", "roe"))
  end

  test "restart command: no subdir (standard layout) is just the boot command" do
    assert_equal "kamal app boot", restore_restart_command(Cfg.new("kamal", nil, "roe"))
  end

  test "restart command: unknown deploy target defaults to kamal" do
    assert_equal "cd current && kamal app boot", restore_restart_command(Cfg.new(nil, "current", "roe"))
  end

  test "roe folder label falls back when the peer folder is unknown" do
    assert_equal "your Roe folder", restore_roe_folder_label(Cfg.new("kamal", "current", nil))
    assert_equal "roe-dev", restore_roe_folder_label(Cfg.new("kamal", "current", "roe-dev"))
  end

  test "fly sync-secrets command includes the app + rails subdir" do
    assert_equal "cd current && bin/rails roe:fly:sync_secrets APP=my-app",
                 fly_sync_secrets_command(Cfg.new("fly", "current", "roe"), "my-app")
  end

  test "fly sync-secrets command without a subdir is bare" do
    assert_equal "bin/rails roe:fly:sync_secrets APP=my-app",
                 fly_sync_secrets_command(Cfg.new("fly", nil, "roe"), "my-app")
  end

  test "fly sync-secrets command falls back when the app name is blank" do
    assert_equal "cd current && bin/rails roe:fly:sync_secrets APP=your-fly-app",
                 fly_sync_secrets_command(Cfg.new("fly", "current", "roe"), nil)
  end

  test "running_on_fly? reflects FLY_APP_NAME" do
    original = ENV["FLY_APP_NAME"]
    ENV["FLY_APP_NAME"] = "my-app"
    assert running_on_fly?
    ENV.delete("FLY_APP_NAME")
    refute running_on_fly?
  ensure
    original.nil? ? ENV.delete("FLY_APP_NAME") : (ENV["FLY_APP_NAME"] = original)
  end

  test "singular vs plural wording" do
    assert_match(/1 file changed/,  collapse_sync_paths(%w[documentation/roe/a.md]).first)
    assert_match(/2 files changed/, collapse_sync_paths(%w[documentation/roe/a.md documentation/roe/b.md]).first)
  end

  test "ungrouped paths pass through, sorted" do
    assert_equal %w[a.md b.md], collapse_sync_paths(%w[b.md a.md])
  end

  test "a similarly-named sibling prefix is NOT collapsed" do
    rows = collapse_sync_paths(%w[documentation/roego/x.md documentation/roe/y.md])
    assert_equal 2, rows.size
    assert_includes rows, "documentation/roego/x.md"
    assert(rows.any? { |r| r.start_with?("Roe documentation") })
  end

  test "collapsed_sync_count returns the grouped tally" do
    assert_equal 1, collapsed_sync_count(%w[documentation/roe/a.md documentation/roe/b.md])
    assert_equal 2, collapsed_sync_count(%w[documentation/roe/a.md posts/x.md])
    assert_equal 0, collapsed_sync_count([])
    assert_equal 0, collapsed_sync_count(nil)
  end
end
