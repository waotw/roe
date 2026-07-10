require "test_helper"
require "tmpdir"
require "fileutils"
require "rubygems/package"
require "zlib"
require "stringio"

module SiteSync
  class TarArchiveTest < ActiveSupport::TestCase
    def setup
      @src = Dir.mktmpdir("tar-src")
      @dst = Dir.mktmpdir("tar-dst")
    end

    def teardown
      [ @src, @dst ].each { |d| FileUtils.remove_entry(d) if d && Dir.exist?(d) }
    end

    def write(root, rel, content = "x")
      full = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(full))
      File.binwrite(full, content)
      full
    end

    # Build a raw gzip tar with arbitrary entry names — needed to exercise
    # malicious/excluded entries that TarArchive.pack would never itself emit.
    def make_targz(entries)
      io = StringIO.new(+"".b)
      Zlib::GzipWriter.wrap(io) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          entries.each do |name, content|
            tar.add_file_simple(name, 0o644, content.bytesize) { |o| o.write(content) }
          end
        end
      end
      io.string
    end

    # ------------------------------------------------------------- round-trip

    test "packs and unpacks a nested file set byte-for-byte" do
      write(@src, "posts/a.md", "hello world")
      write(@src, "site.yml", "title: x")
      write(@src, "media/img.bin", "\x00\x01\xFF\x10".b)
      paths = [ "posts/a.md", "site.yml", "media/img.bin" ]

      bytes = TarArchive.pack(root: @src, paths: paths)
      written = TarArchive.unpack(bytes, dest: @dst)

      assert_equal paths.sort, written
      assert_equal "hello world", File.read(File.join(@dst, "posts/a.md"))
      assert_equal "title: x", File.read(File.join(@dst, "site.yml"))
      assert_equal File.binread(File.join(@src, "media/img.bin")),
                   File.binread(File.join(@dst, "media/img.bin"))
    end

    test "pack skips paths that don't exist (vanished between diff and pack)" do
      write(@src, "real.md", "real")
      bytes = TarArchive.pack(root: @src, paths: [ "real.md", "ghost.md" ])
      assert_equal [ "real.md" ], TarArchive.unpack(bytes, dest: @dst)
    end

    test "pack skips symlinks" do
      write(@src, "real.md", "real")
      File.symlink(File.join(@src, "real.md"), File.join(@src, "link.md"))
      bytes = TarArchive.pack(root: @src, paths: [ "real.md", "link.md" ])
      assert_equal [ "real.md" ], TarArchive.unpack(bytes, dest: @dst)
    end

    # ---------------------------------------------------------------- security

    test "unpack refuses to write Ledger-excluded paths (secrets, db)" do
      bytes = make_targz(
        "system/secrets/master.key"  => "SECRET",
        "db/prod.sqlite3"            => "DB",
        "posts/keep.md"             => "keep"
      )
      written = TarArchive.unpack(bytes, dest: @dst)

      assert_equal [ "posts/keep.md" ], written
      refute File.exist?(File.join(@dst, "system/secrets/master.key")), "must never write a secret from an archive"
      refute File.exist?(File.join(@dst, "db/prod.sqlite3"))
    end

    test "unpack raises on a ../ path-traversal entry" do
      bytes = make_targz("../escape.md" => "pwned")
      assert_raises(TarArchive::UnsafeEntry) { TarArchive.unpack(bytes, dest: @dst) }
      refute File.exist?(File.join(File.dirname(@dst), "escape.md"))
    end

    test "unpack raises on an absolute-path entry" do
      bytes = make_targz("/etc/roe-pwned" => "pwned")
      assert_raises(TarArchive::UnsafeEntry) { TarArchive.unpack(bytes, dest: @dst) }
    end

    test "unpack returns written paths sorted" do
      bytes = make_targz("z.md" => "z", "a.md" => "a", "m/n.md" => "n")
      assert_equal [ "a.md", "m/n.md", "z.md" ], TarArchive.unpack(bytes, dest: @dst)
    end

    test "safe_relative_path normalizes a nested entry within the root" do
      assert_equal "posts/a.md", TarArchive.safe_relative_path("posts/a.md", @dst)
      assert_equal "posts/a.md", TarArchive.safe_relative_path("./posts/a.md", @dst)
    end
  end
end
