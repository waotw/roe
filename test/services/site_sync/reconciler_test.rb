require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

module SiteSync
  # The three-way reconciler is the safety core of bi-directional sync:
  # it must never mislabel a genuine both-sides-diverged conflict as a
  # safe one-way propagation (that's silent data loss). These pin every
  # cell of the state table plus the content-hash confirmation.
  class ReconcilerTest < ActiveSupport::TestCase
    # {size, mtime} entry helper.
    def e(size, mtime)
      { "size" => size, "mtime" => mtime }
    end

    def reconcile(baseline:, local:, peer:)
      Reconciler.reconcile(baseline: baseline, local: local, peer: peer)
    end

    # --------------------------------------------------------- no-op / one-way

    test "identical baseline/local/peer yields nothing to do" do
      m = { "a.md" => e(1, 100) }
      r = reconcile(baseline: m, local: m, peer: m)
      assert_equal [], r.push + r.pull + r.push_delete + r.pull_delete + r.converged
      refute r.any_conflicts?
    end

    test "local-only add/modify → push; local-only delete → push_delete" do
      base = { "keep.md" => e(1, 100), "mod.md" => e(1, 100), "gone.md" => e(1, 100) }
      local = { "keep.md" => e(1, 100), "mod.md" => e(2, 200), "gone.md" => e(1, 100), "new.md" => e(1, 100) }
      peer  = base

      r = reconcile(baseline: base, local: local, peer: peer)
      assert_equal [ "mod.md", "new.md" ], r.push
      assert_empty r.push_delete
      refute r.any_conflicts?

      # delete locally, unchanged on peer → propagate the delete
      r2 = reconcile(baseline: base, local: { "keep.md" => e(1, 100), "mod.md" => e(1, 100) }, peer: base)
      assert_equal [ "gone.md" ], r2.push_delete
    end

    test "peer-only add/modify → pull; peer-only delete → pull_delete" do
      base = { "keep.md" => e(1, 100), "mod.md" => e(1, 100) }
      peer = { "keep.md" => e(1, 100), "mod.md" => e(9, 900), "fromlive.md" => e(1, 100) }

      r = reconcile(baseline: base, local: base, peer: peer)
      assert_equal [ "fromlive.md", "mod.md" ], r.pull
      assert_empty r.pull_delete

      r2 = reconcile(baseline: base, local: base, peer: { "keep.md" => e(1, 100) })
      assert_equal [ "mod.md" ], r2.pull_delete
    end

    test "both sides made the identical change → converged, no conflict, no transfer" do
      base  = { "a.md" => e(1, 100) }
      both  = { "a.md" => e(2, 200) } # same new size+mtime on each side
      r = reconcile(baseline: base, local: both, peer: both)
      assert_equal [ "a.md" ], r.converged
      assert_empty r.push
      assert_empty r.pull
      refute r.any_conflicts?
    end

    # ------------------------------------------------------------- conflicts

    test "edit vs edit (diverged) is an EDIT_EDIT conflict" do
      base = { "a.md" => e(1, 100) }
      r = reconcile(baseline: base, local: { "a.md" => e(2, 200) }, peer: { "a.md" => e(3, 300) })
      assert_equal 1, r.conflicts.size
      c = r.conflicts.first
      assert_equal "a.md", c.path
      assert_equal Reconciler::EDIT_EDIT, c.type
      assert_equal e(2, 200), c.local
      assert_equal e(3, 300), c.peer
    end

    test "local edit vs peer delete → EDIT_DELETE; local delete vs peer edit → DELETE_EDIT" do
      base = { "a.md" => e(1, 100) }

      r1 = reconcile(baseline: base, local: { "a.md" => e(2, 200) }, peer: {})
      assert_equal Reconciler::EDIT_DELETE, r1.conflicts.first.type

      r2 = reconcile(baseline: base, local: {}, peer: { "a.md" => e(3, 300) })
      assert_equal Reconciler::DELETE_EDIT, r2.conflicts.first.type
    end

    test "both add the same path with different content → EDIT_EDIT conflict" do
      r = reconcile(baseline: {}, local: { "new.md" => e(2, 200) }, peer: { "new.md" => e(3, 300) })
      assert_equal Reconciler::EDIT_EDIT, r.conflicts.first.type
    end

    # --------------------------------------------------- hash confirmation

    test "hash_candidates are only same-size edit/edit conflicts" do
      base = { "same.md" => e(5, 100), "diff.md" => e(5, 100) }
      # same.md: same size (5), different mtime → candidate
      # diff.md: different size → definitely a real conflict, not a candidate
      local = { "same.md" => e(5, 200), "diff.md" => e(7, 200) }
      peer  = { "same.md" => e(5, 300), "diff.md" => e(9, 300) }

      r = reconcile(baseline: base, local: local, peer: peer)
      assert_equal 2, r.conflicts.size
      assert_equal [ "same.md" ], Reconciler.hash_candidates(r)
    end

    test "confirm reclassifies a same-content candidate as converged, keeps a real one" do
      base = { "skew.md" => e(5, 100), "real.md" => e(5, 100) }
      local = { "skew.md" => e(5, 200), "real.md" => e(5, 200) }
      peer  = { "skew.md" => e(5, 300), "real.md" => e(5, 300) }
      r = reconcile(baseline: base, local: local, peer: peer)

      # skew.md: identical bytes (mtime skew) → converged
      # real.md: different bytes → stays a conflict
      confirmed = Reconciler.confirm(
        r,
        local_hashes: { "skew.md" => "aaa", "real.md" => "bbb" },
        peer_hashes:  { "skew.md" => "aaa", "real.md" => "ccc" }
      )
      assert_equal [ "skew.md" ], confirmed.converged
      assert_equal [ "real.md" ], confirmed.conflicts.map(&:path)
    end

    test "confirm keeps a candidate as a conflict when a hash is missing (fail safe)" do
      base = { "a.md" => e(5, 100) }
      r = reconcile(baseline: base, local: { "a.md" => e(5, 200) }, peer: { "a.md" => e(5, 300) })
      confirmed = Reconciler.confirm(r, local_hashes: { "a.md" => "aaa" }, peer_hashes: {})
      assert_equal [ "a.md" ], confirmed.conflicts.map(&:path), "no peer hash → assume real conflict"
    end

    # ------------------------------------------------------------ hashes_for

    test "hashes_for returns SHA256 per existing file and skips missing" do
      dir = Dir.mktmpdir("recon-hash")
      begin
        FileUtils.mkdir_p(File.join(dir, "posts"))
        File.write(File.join(dir, "posts/a.md"), "hello")
        hashes = Reconciler.hashes_for([ "posts/a.md", "posts/missing.md" ], root: dir)
        assert_equal Digest::SHA256.hexdigest("hello"), hashes["posts/a.md"]
        refute hashes.key?("posts/missing.md")
      ensure
        FileUtils.remove_entry(dir)
      end
    end
  end
end
