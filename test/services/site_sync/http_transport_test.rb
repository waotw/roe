require "test_helper"
require "tmpdir"
require "fileutils"

module SiteSync
  # HttpTransport moves /site bytes over the Exchange peer-call channel.
  # These tests stub the peer (Exchange) and exercise the real pack/unpack
  # + filesystem effects against the test /site, so we verify the transport
  # sends the right payload on push, writes the right files on pull, and
  # hardlinks unchanged files on backup.
  class HttpTransportTest < ActiveSupport::TestCase
    SITE = RoeSitePaths::SITE_PATH

    def setup
      @created = []
      # Never touch the network; push's post-upload bookkeeping is a no-op.
      Exchange.stubs(:refresh_peer_ledger!).returns(true)
      Exchange.stubs(:reconcile_peer_content!).returns(true)
    end

    def teardown
      @created.each { |p| FileUtils.rm_rf(p) }
    end

    def site_write(rel, content)
      full = File.join(SITE, rel)
      FileUtils.mkdir_p(File.dirname(full))
      File.binwrite(full, content)
      @created << full
      full
    end

    # ----------------------------------------------------------------- push

    test "push packs added+modified, sends per-file manifest, and forwards deletions" do
      site_write("posts/http_new.md", "NEW")
      site_write("posts/http_mod.md", "MOD")
      diff = { added: [ "posts/http_new.md" ], modified: [ "posts/http_mod.md" ], deleted: [ "posts/http_gone.md" ] }

      recorded = {}
      Exchange.stubs(:upload_files).with do |archive_bytes:, manifest:, deleted:|
        recorded[:archive]  = archive_bytes
        recorded[:manifest] = manifest
        recorded[:deleted]  = deleted
        true
      end.returns({ "ok" => true })

      HttpTransport.push_local_to_live!(diff: diff)

      assert_equal [ "posts/http_gone.md" ], recorded[:deleted]
      assert_equal %w[posts/http_mod.md posts/http_new.md], recorded[:manifest].keys.sort
      assert recorded[:manifest]["posts/http_new.md"]["mtime"].is_a?(Integer)

      dst = Dir.mktmpdir("push-unpack")
      @created << dst
      written = TarArchive.unpack(recorded[:archive], dest: dst)
      assert_equal %w[posts/http_mod.md posts/http_new.md], written
      assert_equal "NEW", File.read(File.join(dst, "posts/http_new.md"))
    end

    test "push raises when the peer upload fails" do
      site_write("posts/http_x.md", "X")
      Exchange.stubs(:upload_files).returns(nil)
      assert_raises(HttpTransport::HttpTransportError) do
        HttpTransport.push_local_to_live!(diff: { added: [ "posts/http_x.md" ], modified: [], deleted: [] })
      end
    end

    # ----------------------------------------------------------------- pull

    test "pull downloads changed files, restores mtimes, and deletes removed ones" do
      # Peer content to be pulled, built into a real archive.
      src = Dir.mktmpdir("pull-src")
      @created << src
      FileUtils.mkdir_p(File.join(src, "pulled"))
      File.write(File.join(src, "pulled/a.md"), "PULLED")
      archive = TarArchive.pack(root: src, paths: [ "pulled/a.md" ])
      @created << File.join(SITE, "pulled") # created under /site by the pull

      # A local file the pull should delete.
      gone = site_write("posts/pull_gone.md", "bye")

      mtime = 1_620_000_000
      Exchange.stubs(:fetch_peer_file_states)
              .returns({ "pulled/a.md" => { "size" => 6, "mtime" => mtime } })
      Exchange.stubs(:download_files).returns(archive)
      Ledger.stubs(:write_current!).returns({})

      diff = { added: [ "pulled/a.md" ], modified: [], deleted: [ "posts/pull_gone.md" ] }
      HttpTransport.pull_live_to_local!(diff: diff)

      landed = File.join(SITE, "pulled/a.md")
      assert_equal "PULLED", File.read(landed)
      assert_equal mtime, File.stat(landed).mtime.to_i
      refute File.exist?(gone)
    end

    # --------------------------------------------------------------- backup

    test "backup hardlinks files unchanged since the previous snapshot" do
      tmp  = Dir.mktmpdir("http-backup")
      @created << tmp
      root = File.join(tmp, "production")
      FileUtils.mkdir_p(root)
      dir1 = File.join(root, "2026-01-01-000000")
      dir2 = File.join(root, "2026-01-02-000000")

      HttpTransport.stubs(:new_backup_dir)
                   .returns([ dir1, root, "2026-01-01-000000" ])
                   .then.returns([ dir2, root, "2026-01-02-000000" ])

      # Peer manifest: two files with fixed size+mtime.
      peer_files = {
        "a.md" => { "size" => 1, "mtime" => 1_000 },
        "b.md" => { "size" => 1, "mtime" => 2_000 }
      }
      Exchange.stubs(:fetch_peer_manifest).returns({ "files" => peer_files })

      # Archive the peer serves (bytes only; mtimes come from the manifest).
      src = Dir.mktmpdir("backup-src")
      @created << src
      File.write(File.join(src, "a.md"), "x")
      File.write(File.join(src, "b.md"), "x")
      full_archive = TarArchive.pack(root: src, paths: [ "a.md", "b.md" ])
      Exchange.stubs(:download_files).returns(full_archive)

      # First snapshot: nothing to link against, both files downloaded.
      out1 = HttpTransport.backup_live_to_local!
      assert_equal dir1, out1
      assert_equal 1_000, File.stat(File.join(dir1, "a.md")).mtime.to_i

      # Second snapshot: files unchanged → hardlinked from dir1, not re-fetched.
      out2 = HttpTransport.backup_live_to_local!
      assert_equal dir2, out2
      assert File.identical?(File.join(dir1, "a.md"), File.join(dir2, "a.md")),
             "unchanged file should be hardlinked from the previous snapshot"
      assert File.identical?(File.join(dir1, "b.md"), File.join(dir2, "b.md"))
    end

    test "backup raises when the peer manifest is unavailable" do
      Exchange.stubs(:fetch_peer_manifest).returns(nil)
      assert_raises(HttpTransport::HttpTransportError) { HttpTransport.backup_live_to_local! }
    end
  end
end
