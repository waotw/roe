require "test_helper"
require "tmpdir"
require "fileutils"

module SiteSync
  # The Ledger is the foundation of Site Sync: it fingerprints /site, computes
  # the add/modify/delete diff every transport pushes, and provides the
  # baseline the (future) bi-directional conflict layer will reconcile against.
  # These tests pin its behaviour down hard so that work can build on it.
  class LedgerTest < ActiveSupport::TestCase
    def setup
      @dir = Dir.mktmpdir("ledger-test")
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
    end

    def write(relpath, content = "x")
      full = File.join(@dir, relpath)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
      full
    end

    def ledger
      Ledger.new(site_path: @dir)
    end

    # ---------------------------------------------------------------- manifest

    test "a missing site path yields an empty manifest, not a crash" do
      assert_equal({}, Ledger.new(site_path: File.join(@dir, "nope")).current_manifest)
    end

    test "includes root and nested files with size + integer mtime" do
      write("posts/hello.md", "hello")   # 5 bytes
      write("site.yml", "title: x")
      m = ledger.current_manifest
      assert_equal %w[posts/hello.md site.yml], m.keys.sort
      assert_equal 5, m["posts/hello.md"]["size"]
      assert_kind_of Integer, m["posts/hello.md"]["mtime"]
    end

    test "excludes db, .git and .sync-backups top-level subtrees" do
      write("db/production.sqlite3", "db")
      write("db/nested/x", "db")
      write(".git/config", "git")
      write(".sync-backups/snap/x.md", "bak")
      write("posts/keep.md", "keep")
      assert_equal ["posts/keep.md"], ledger.current_manifest.keys
    end

    test "excludes system/secrets subtree but keeps other system files" do
      write("system/secrets/master.key", "k")
      write("system/secrets/credentials.yml.enc", "k")
      write("system/global/deploy.yml", "target: fly")
      keys = ledger.current_manifest.keys
      refute_includes keys, "system/secrets/master.key"
      refute_includes keys, "system/secrets/credentials.yml.enc"
      assert_includes keys, "system/global/deploy.yml"
    end

    test "excludes noise files by name anywhere in the tree" do
      write(".DS_Store", "junk")
      write("posts/.DS_Store", "junk")
      write(".sync-state.json", "{}")
      write("system/global/.last_deploy.yml", "x")
      write("posts/real.md", "real")
      assert_equal ["posts/real.md"], ledger.current_manifest.keys
    end

    test "directories are never entries; only files" do
      FileUtils.mkdir_p(File.join(@dir, "empty_dir"))
      write("posts/x.md", "x")
      assert_equal ["posts/x.md"], ledger.current_manifest.keys
    end

    test "symlinks are skipped (only the real file is tracked)" do
      write("real.md", "real")
      File.symlink(File.join(@dir, "real.md"), File.join(@dir, "link.md"))
      keys = ledger.current_manifest.keys
      assert_includes keys, "real.md"
      refute_includes keys, "link.md"
    end

    test "non-excluded dotfiles ARE included" do
      write(".nojekyll", "")
      write("posts/x.md", "x")
      assert_includes ledger.current_manifest.keys, ".nojekyll"
    end

    # -------------------------------------------------------------------- diff

    test "diff reports added, deleted, size-changed and mtime-changed; ignores unchanged" do
      recorded = {
        "keep.md"  => { "size" => 1, "mtime" => 100 },
        "gone.md"  => { "size" => 1, "mtime" => 100 },
        "size.md"  => { "size" => 1, "mtime" => 100 },
        "mtime.md" => { "size" => 1, "mtime" => 100 }
      }
      current = {
        "keep.md"  => { "size" => 1, "mtime" => 100 },   # unchanged
        "size.md"  => { "size" => 2, "mtime" => 100 },   # size differs
        "mtime.md" => { "size" => 1, "mtime" => 200 },   # mtime differs
        "new.md"   => { "size" => 1, "mtime" => 100 }    # added
      }
      d = Ledger.diff(current, recorded)
      assert_equal ["new.md"], d[:added]
      assert_equal ["gone.md"], d[:deleted]
      assert_equal ["mtime.md", "size.md"], d[:modified]   # sorted
    end

    test "diff treats a nil baseline as everything-added (sorted)" do
      current = { "b.md" => { "size" => 1, "mtime" => 1 }, "a.md" => { "size" => 1, "mtime" => 1 } }
      d = Ledger.diff(current, nil)
      assert_equal ["a.md", "b.md"], d[:added]
      assert_empty d[:deleted]
      assert_empty d[:modified]
    end

    test "diff of identical maps is empty" do
      m = { "a.md" => { "size" => 1, "mtime" => 1 } }
      d = Ledger.diff(m, m)
      assert_empty d[:added]
      assert_empty d[:deleted]
      assert_empty d[:modified]
    end

    # ------------------------------------------------------------- fingerprint

    test "fingerprint is order-independent over the path map (cross-OS safe)" do
      a = { "a.md" => { "size" => 1, "mtime" => 1 }, "b.md" => { "size" => 2, "mtime" => 2 } }
      b = { "b.md" => { "size" => 2, "mtime" => 2 }, "a.md" => { "size" => 1, "mtime" => 1 } }
      assert_equal Ledger.fingerprint_of(a), Ledger.fingerprint_of(b)
    end

    test "fingerprint changes when any file's size/mtime changes" do
      a = { "a.md" => { "size" => 1, "mtime" => 1 } }
      b = { "a.md" => { "size" => 2, "mtime" => 1 } }
      refute_equal Ledger.fingerprint_of(a), Ledger.fingerprint_of(b)
    end

    test "fingerprint_for walks a dir and equals fingerprint_of its manifest" do
      write("posts/x.md", "x")
      assert_equal Ledger.fingerprint_of(ledger.current_manifest), Ledger.fingerprint_for(@dir)
    end

    # -------------------------------------------------- write / recorded round-trip

    test "write_current! persists a wrapped ledger and recorded round-trips the files" do
      write("posts/x.md", "x")
      manifest = ledger.current_manifest
      data = ledger.write_current!

      assert_equal Rails.env.to_s, data["env"]
      assert_equal Ledger.fingerprint_of(manifest), data["fingerprint"]
      assert data["version"].present?

      recorded = ledger.recorded_manifest
      assert_equal manifest, recorded["files"]
      assert_equal data["fingerprint"], recorded["fingerprint"]
    end

    test "recorded_manifest is nil when no ledger has been written" do
      assert_nil ledger.recorded_manifest
    end

    test "recorded_manifest returns nil (never raises) on corrupt JSON" do
      File.write(File.join(@dir, Ledger::LEDGER_FILENAME), "{ not valid json")
      assert_nil ledger.recorded_manifest
    end

    test "writing the ledger does not make the tree look drifted (no self-drift)" do
      write("posts/x.md", "x")
      before = ledger.current_manifest
      ledger.write_current!
      after = ledger.current_manifest
      assert_equal before, after, "the .sync-state.json we just wrote must be excluded"

      d = Ledger.diff(after, ledger.recorded_manifest["files"])
      assert_empty d[:added]
      assert_empty d[:modified]
      assert_empty d[:deleted]
    end

    # --------------------------------------------------------- shape contract

    test "current is unwrapped, recorded is wrapped — diff must use recorded['files']" do
      write("posts/x.md", "x")
      ledger.write_current!
      current  = ledger.current_manifest
      recorded = ledger.recorded_manifest

      # current is a bare path => {size,mtime} map
      assert current.key?("posts/x.md")
      refute current.key?("files")

      # recorded wraps it under "files" (plus version/fingerprint/env)
      assert recorded.key?("files")
      assert recorded.key?("version")

      # the correct call is diff(current, recorded["files"]) — clean, no drift
      assert_empty Ledger.diff(current, recorded["files"]).values.flatten
    end

    # ------------------------------------------------ public excluded? contract

    test "Ledger.excluded? matches manifest exclusion (drives the tar unpacker)" do
      assert Ledger.excluded?("db/x.sqlite3")
      assert Ledger.excluded?(".git/config")
      assert Ledger.excluded?("system/secrets/master.key")
      assert Ledger.excluded?("posts/.DS_Store")
      assert Ledger.excluded?(".sync-state.json")

      refute Ledger.excluded?("posts/hello.md")
      refute Ledger.excluded?("system/global/deploy.yml")
      refute Ledger.excluded?(".nojekyll")
    end
  end
end
