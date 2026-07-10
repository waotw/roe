require "test_helper"
require "tmpdir"
require "fileutils"

module SiteSync
  # Stress + property tests for the Ledger — the foundation the upcoming
  # bi-directional conflict layer stands on. The load-bearing invariant:
  # two /site trees with identical content fingerprint identically and
  # diff to nothing, at scale and with awkward filenames. If that ever
  # breaks, conflict detection would cry wolf on every sync.
  class LedgerScaleTest < ActiveSupport::TestCase
    def setup
      @a = Dir.mktmpdir("ledger-a")
      @b = Dir.mktmpdir("ledger-b")
    end

    def teardown
      [ @a, @b ].each { |d| FileUtils.remove_entry(d) if d && Dir.exist?(d) }
    end

    # A big, realistic-ish tree: nested dirs, varied sizes, awkward names,
    # plus excluded noise (variants/secrets/db). Deterministic content so a
    # clone is byte-identical.
    def build_tree(root, count: 800)
      count.times do |i|
        dir = File.join(root, "posts", "y#{i % 12}", "m#{i % 6}")
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "post-#{i}.md"), "content ##{i}\n" * ((i % 50) + 1))
      end
      [ "a file with spaces.md", "ünïçodé-café.md", "dots.in.name.md", "dash--x.md" ].each_with_index do |name, i|
        File.write(File.join(root, "posts", name), "x" * (i + 1))
      end
      FileUtils.mkdir_p(File.join(root, "media/images/variants"))
      File.write(File.join(root, "media/images/photo.jpg"), "img")
      File.write(File.join(root, "media/images/variants/photo-small.jpg"), "variant") # excluded
      FileUtils.mkdir_p(File.join(root, "system/secrets"))
      File.write(File.join(root, "system/secrets/master.key"), "SECRET")             # excluded
      FileUtils.mkdir_p(File.join(root, "db"))
      File.write(File.join(root, "db/prod.sqlite3"), "DB")                           # excluded
    end

    # Clone src → dst preserving mtime — what a correct sync leaves behind.
    def clone_tree(src, dst)
      FileUtils.cp_r(File.join(src, "."), dst, preserve: true)
    end

    def manifest(root)
      Ledger.new(site_path: root).current_manifest
    end

    test "identical trees fingerprint identically and diff to nothing (the sync invariant)" do
      build_tree(@a, count: 800)
      clone_tree(@a, @b)

      man_a = manifest(@a)
      man_b = manifest(@b)

      assert_operator man_a.size, :>, 800, "sanity: the tree is actually large"
      assert_equal man_a.keys.sort, man_b.keys.sort
      assert_equal Ledger.fingerprint_of(man_a), Ledger.fingerprint_of(man_b),
                   "clones must fingerprint identically or conflict detection cries wolf"
      d = Ledger.diff(man_a, man_b)
      assert_empty d[:added]
      assert_empty d[:deleted]
      assert_empty d[:modified]
    end

    test "awkward filenames (spaces, unicode, dots) round-trip and fingerprint stably" do
      build_tree(@a, count: 20)
      clone_tree(@a, @b)
      keys = manifest(@a).keys
      assert_includes keys, "posts/a file with spaces.md"
      assert_includes keys, "posts/ünïçodé-café.md"
      assert_includes keys, "posts/dots.in.name.md"
      assert_equal Ledger.fingerprint_of(manifest(@a)), Ledger.fingerprint_of(manifest(@b))
    end

    test "exclusions hold at scale — no variants/secrets/db in a big tree" do
      build_tree(@a, count: 300)
      keys = manifest(@a).keys
      assert(keys.none? { |k| k.include?("/variants/") })
      assert(keys.none? { |k| k.start_with?("system/secrets/") })
      assert(keys.none? { |k| k.start_with?("db/") })
      assert_includes keys, "media/images/photo.jpg"
    end

    test "diff isolates exactly the changed files against a shared baseline" do
      build_tree(@a, count: 500)
      clone_tree(@a, @b)
      base = manifest(@b) # the last-synced baseline both sides shared

      File.write(File.join(@a, "posts", "brand-new.md"), "new")
      changed = File.join(@a, "posts", "y0", "m0", "post-0.md")
      File.write(changed, "a clearly different size of content here")
      deleted_rel = "posts/y1/m1/post-13.md" # 13 % 12 = 1, 13 % 6 = 1
      File.delete(File.join(@a, deleted_rel))

      d = Ledger.diff(manifest(@a), base)
      assert_equal [ "posts/brand-new.md" ], d[:added]
      assert_equal [ deleted_rel ], d[:deleted]
      assert_equal [ "posts/y0/m0/post-0.md" ], d[:modified]
    end

    test "mtime is second-granular: a sub-second re-touch is invisible, a whole second is a change" do
      f = File.join(@a, "x.md")
      File.write(f, "x")
      base = manifest(@a)
      sec = File.mtime(f).to_i

      File.utime(File.atime(f), Time.at(sec + 0.4), f) # same whole second
      assert_equal Ledger.fingerprint_of(base), Ledger.fingerprint_of(manifest(@a)),
                   "sub-second mtime jitter must not register as drift"

      File.utime(File.atime(f), Time.at(sec + 1), f) # next whole second
      refute_equal Ledger.fingerprint_of(base), Ledger.fingerprint_of(manifest(@a))
    end

    test "walking ~1k files is not pathologically slow" do
      build_tree(@a, count: 1000)
      started = Time.now
      man = manifest(@a)
      elapsed = Time.now - started
      assert_operator man.size, :>, 1000
      assert_operator elapsed, :<, 5.0, "ledger walk of ~1k files took #{elapsed.round(2)}s"
    end
  end
end
