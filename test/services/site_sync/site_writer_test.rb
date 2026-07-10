require "test_helper"
require "tmpdir"
require "fileutils"

module SiteSync
  # SiteWriter applies a received file set into a site root: restoring
  # mtimes from a manifest and deleting removed paths. Both the pull
  # transport and the upload endpoint lean on it, so its safety guards
  # (never delete a secret, never escape the root) are pinned here.
  class SiteWriterTest < ActiveSupport::TestCase
    def setup
      @root = Dir.mktmpdir("site-writer")
    end

    def teardown
      FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
    end

    def write(rel, content = "x")
      full = File.join(@root, rel)
      FileUtils.mkdir_p(File.dirname(full))
      File.binwrite(full, content)
      full
    end

    # -------------------------------------------------------- restore_mtimes

    test "restore_mtimes stamps each file's mtime from the manifest" do
      full = write("posts/a.md", "hello")
      SiteWriter.restore_mtimes(root: @root, manifest: {
        "posts/a.md" => { "size" => 5, "mtime" => 1_600_000_000 }
      })
      assert_equal 1_600_000_000, File.stat(full).mtime.to_i
    end

    test "restore_mtimes ignores manifest entries whose file is absent or mtime nil" do
      write("posts/present.md", "x")
      # Neither of these should raise.
      SiteWriter.restore_mtimes(root: @root, manifest: {
        "posts/absent.md"  => { "size" => 1, "mtime" => 123 },
        "posts/present.md" => { "size" => 1 } # no mtime
      })
      assert File.exist?(File.join(@root, "posts/present.md"))
    end

    test "restore_mtimes tolerates a nil manifest" do
      assert_nothing_raised { SiteWriter.restore_mtimes(root: @root, manifest: nil) }
    end

    # ----------------------------------------------------------- delete_paths

    test "delete_paths removes listed files and reports what it removed" do
      write("posts/gone.md", "bye")
      write("posts/keep.md", "stay")

      removed = SiteWriter.delete_paths(root: @root, paths: [ "posts/gone.md", "posts/never-existed.md" ])

      assert_equal [ "posts/gone.md" ], removed
      refute File.exist?(File.join(@root, "posts/gone.md"))
      assert File.exist?(File.join(@root, "posts/keep.md"))
    end

    test "delete_paths refuses traversal and absolute paths" do
      outside = File.join(File.dirname(@root), "victim.md")
      File.write(outside, "precious")
      begin
        removed = SiteWriter.delete_paths(root: @root, paths: [ "../victim.md", "/etc/hosts" ])
        assert_empty removed
        assert File.exist?(outside), "must never delete a file outside the root"
      ensure
        FileUtils.rm_f(outside)
      end
    end

    test "delete_paths refuses Ledger-excluded paths (never deletes a secret)" do
      write("system/secrets/master.key", "KEY")
      write("db/prod.sqlite3", "DB")

      removed = SiteWriter.delete_paths(root: @root, paths: [ "system/secrets/master.key", "db/prod.sqlite3" ])

      assert_empty removed
      assert File.exist?(File.join(@root, "system/secrets/master.key")), "a sync message must never delete a secret"
      assert File.exist?(File.join(@root, "db/prod.sqlite3"))
    end
  end
end
