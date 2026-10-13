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

    # A video rendition is far bigger than a batch, and one request that size
    # died on the way to the live site. Large files go on their own, in
    # pieces, before the batches; deletions still wait for the last batch.
    test "files over the batch limit go up in pieces, first, and deletions still come last" do
      site_write("media/video/variants/big-720p.mp4", "B" * 300)
      site_write("posts/small.md", "S")
      stub_const(HttpTransport, :PUSH_BATCH_MAX_BYTES, 100)

      order = []
      Exchange.stubs(:upload_large_file).with { |rel, **| order << [ :large, rel ]; true }.returns(true)
      Exchange.stubs(:upload_files).with do |archive_bytes:, deleted:, **|
        order << [ :batch, TarArchive.unpack(archive_bytes, dest: Dir.mktmpdir.tap { |d| @created << d }), deleted ]
        true
      end.returns({ "ok" => true })

      HttpTransport.push_local_to_live!(diff: { added: %w[media/video/variants/big-720p.mp4 posts/small.md], modified: [], deleted: [ "posts/old.md" ] })

      assert_equal [ :large, "media/video/variants/big-720p.mp4" ], order.first
      assert_equal [ :batch, [ "posts/small.md" ], [ "posts/old.md" ] ], order.last
    end

    test "a large file that can't be sent fails the push with the reason" do
      site_write("media/video/variants/huge-720p.mp4", "H" * 300)
      stub_const(HttpTransport, :PUSH_BATCH_MAX_BYTES, 100)
      Exchange.stubs(:upload_large_file).raises(Exchange::ChunkedUploadError, "The live site can't receive large files yet — deploy this version of Roe to it, then sync again.")
      Exchange.expects(:upload_files).never

      error = assert_raises(HttpTransport::HttpTransportError) do
        HttpTransport.push_local_to_live!(diff: { added: [ "media/video/variants/huge-720p.mp4" ], modified: [], deleted: [ "posts/keep.md" ] })
      end
      assert_match(/deploy this version/, error.message)
    end

    # A push of one big video and a few small files used to report "0 of 5
    # files" for the whole of the video's upload, which looked stuck. The
    # transport now reports bytes as well, piece by piece for a large file.
    test "push reports bytes as they go, including each piece of a large file" do
      site_write("media/video/variants/big-720p.mp4", "B" * 300)
      site_write("posts/small.md", "S" * 10)
      stub_const(HttpTransport, :PUSH_BATCH_MAX_BYTES, 100)

      Exchange.stubs(:upload_large_file).with do |_rel, on_bytes:, **|
        on_bytes.call(100)
        on_bytes.call(300)
        true
      end.returns(true)
      Exchange.stubs(:upload_files).returns({ "ok" => true })

      reports = []
      HttpTransport.push_local_to_live!(
        diff: { added: %w[media/video/variants/big-720p.mp4 posts/small.md], modified: [], deleted: [] },
        on_progress: ->(**report) { reports << report }
      )

      assert_equal 310, reports.first[:bytes_total]
      assert_equal [ 0, 100, 300, 300, 310 ], reports.map { |r| r[:bytes_done] }
      assert_equal [ 0, 0, 0, 1, 2 ], reports.map { |r| r[:completed] }
      assert reports.all? { |r| r[:total] == 2 }
    end

    def stub_const(mod, name, value)
      original = mod.const_get(name)
      mod.send(:remove_const, name)
      mod.const_set(name, value)
      @restore_consts ||= []
      @restore_consts << [ mod, name, original ]
    end

    def after_teardown
      Array(@restore_consts).each do |mod, name, original|
        mod.send(:remove_const, name)
        mod.const_set(name, original)
      end
      super
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

    # The bug: a large site's backup pulled every file in one request, which
    # timed out ("backup download from peer failed"). Downloads must chunk by
    # the peer's reported sizes, like the push side does.
    test "backup chunks the download into batches by peer-reported size" do
      %w[ba bb bc].each { |f| site_write("posts/#{f}.md", f.upcase) }
      big = 20 * 1024 * 1024 # each "file" reports 20MB → 25MB cap forces 3 batches
      peer_files = {
        "posts/ba.md" => { "size" => big, "mtime" => 1 },
        "posts/bb.md" => { "size" => big, "mtime" => 1 },
        "posts/bc.md" => { "size" => big, "mtime" => 1 }
      }
      Exchange.stubs(:fetch_peer_manifest).returns({ "files" => peer_files })

      calls = []
      Exchange.stubs(:download_files).with { |paths| calls << paths; true }.returns(
        TarArchive.pack(root: SITE, paths: [ "posts/ba.md" ]),
        TarArchive.pack(root: SITE, paths: [ "posts/bb.md" ]),
        TarArchive.pack(root: SITE, paths: [ "posts/bc.md" ])
      )

      out = HttpTransport.backup_live_to_local!
      @created << out if out

      assert_equal 3, calls.size, "one bounded request per batch, not one big download"
      assert_equal [ [ "posts/ba.md" ], [ "posts/bb.md" ], [ "posts/bc.md" ] ], calls
      %w[ba bb bc].each { |f| assert File.exist?(File.join(out, "posts/#{f}.md")), "#{f} in backup" }
    end

    # A 1.2 GB video in one download failed every time and stopped the sync.
    # Large files and video web versions are left out of live backups now;
    # the rest of the backup still happens.
    test "backup leaves out large files and video web versions" do
      site_write("posts/keep.md", "K")
      site_write("media/video/variants/clip-video.json", "{}")
      peer_files = {
        "posts/keep.md"                        => { "size" => 1, "mtime" => 1 },
        "media/video/variants/clip-video.json" => { "size" => 2, "mtime" => 1 },
        "media/video/variants/clip-720p.mp4"   => { "size" => 5, "mtime" => 1 },
        "media/video/clip.mov"                 => { "size" => BackupPolicy::LIVE_BACKUP_MAX_BYTES + 1, "mtime" => 1 }
      }
      Exchange.stubs(:fetch_peer_manifest).returns({ "files" => peer_files })

      requested = []
      Exchange.stubs(:download_files).with { |paths| requested.concat(paths); true }.returns(
        TarArchive.pack(root: SITE, paths: [ "posts/keep.md", "media/video/variants/clip-video.json" ])
      )

      out = HttpTransport.backup_live_to_local!(files: peer_files.keys)
      @created << out if out

      assert_equal %w[media/video/variants/clip-video.json posts/keep.md], requested.sort
    end

    test "backup of only large files downloads nothing and does not fail" do
      peer_files = { "media/video/clip.mov" => { "size" => BackupPolicy::LIVE_BACKUP_MAX_BYTES + 1, "mtime" => 1 } }
      Exchange.stubs(:fetch_peer_manifest).returns({ "files" => peer_files })
      Exchange.expects(:download_files).never

      assert_nil HttpTransport.backup_live_to_local!(files: peer_files.keys)
    end
  end
end
