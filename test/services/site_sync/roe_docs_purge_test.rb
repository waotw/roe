# frozen_string_literal: true

require "test_helper"

# Roe's documentation used to sync by default. The docs.roe setting now
# defaults to `local`, so an install that updates suddenly stops tracking
# files live already has — and every sync reported them as 108 deletions
# needing confirmation.
#
# They ship with Roe and are always on this computer, so removing them from
# live can't lose anything and the setting is the user's instruction. This is
# the one deletion that shouldn't ask.
class SiteSync::RoeDocsPurgeTest < ActiveSupport::TestCase
  setup do
    @docs = File.join(RoeSitePaths::SITE_PATH, "documentation", "roe")
    FileUtils.mkdir_p(@docs)
    File.write(File.join(@docs, "zz-guide.md"), "# Guide\n")
    SiteSync::Ledger.reset_roe_docs_cache!
  end

  teardown do
    FileUtils.rm_f(File.join(@docs, "zz-guide.md"))
    SiteSync::Ledger.reset_roe_docs_cache!
  end

  def with_mode(mode)
    Documentation.stubs(:roe_docs_mode).returns(mode)
    SiteSync::Ledger.reset_roe_docs_cache!
    yield
  ensure
    Documentation.unstub(:roe_docs_mode)
    SiteSync::Ledger.reset_roe_docs_cache!
  end

  test "local means the live copies are listed for removal" do
    with_mode("local") do
      assert_includes SiteSync::Ledger.roe_docs_to_purge, "documentation/roe/zz-guide.md"
    end
  end

  test "published means nothing is removed" do
    with_mode("published") do
      assert_empty SiteSync::Ledger.roe_docs_to_purge,
        "a site publishing its docs would have them deleted out from under it"
    end
  end

  # delete_paths refuses anything the receiver's own Ledger excludes — which
  # with docs.roe local is these very files. Without the carve-out the purge is
  # accepted and silently does nothing.
  test "the receiver actually removes them despite excluding them" do
    with_mode("local") do
      removed = SiteSync::SiteWriter.delete_paths(
        root: RoeSitePaths::SITE_PATH, paths: [ "documentation/roe/zz-guide.md" ]
      )

      assert_equal [ "documentation/roe/zz-guide.md" ], removed
      assert_not File.exist?(File.join(@docs, "zz-guide.md"))
    end
  end

  # The carve-out is for Roe's own docs and nothing else — a peer must never be
  # able to delete backups, .git or secrets.
  test "everything else excluded is still protected from deletion" do
    protected_paths = SiteSync::Ledger::EXCLUDED_DIRS.map { |dir| "#{dir}/something.md" }

    removed = SiteSync::SiteWriter.delete_paths(
      root: RoeSitePaths::SITE_PATH, paths: protected_paths
    )

    assert_empty removed
  end

  # The direction that actually bit: setting docs.roe to local excludes them
  # from our manifest, so the reconciler read their absence as us deleting 113
  # files and asked before propagating.
  DOC = "documentation/roe/zz-guide.md"
  STATE = { "size" => 1, "mtime" => 1 }.freeze

  test "switching to local doesn't read as us deleting them" do
    with_mode("local") do
      result = SiteSync::Reconciler.reconcile(
        baseline: { DOC => STATE }, local: {}, peer: { DOC => STATE }
      )

      assert_empty result.push_delete, "asked to confirm deleting files the setting just excluded"
      assert_empty result.pull, "would pull back the docs we just chose not to keep"
      assert_empty result.conflicts
    end
  end

  # And the direction from the original report: live excludes them, we don't.
  test "a peer that excludes them isn't treated as having deleted them" do
    with_mode("local") do
      result = SiteSync::Reconciler.reconcile(
        baseline: { DOC => STATE }, local: { DOC => STATE }, peer: {}
      )

      assert_empty result.pull_delete
      assert_empty result.conflicts
    end
  end

  # Published means they're ordinary content again and reconcile normally.
  test "published leaves them in the reconcile" do
    with_mode("published") do
      result = SiteSync::Reconciler.reconcile(
        baseline: {}, local: { DOC => STATE }, peer: {}
      )

      assert_includes result.push, DOC
    end
  end

  # Checker's drift banner never touches the Reconciler — it calls Ledger.diff
  # directly, so the reconciler filter alone left the warning in place.
  test "the drift check doesn't call them deletions either" do
    with_mode("local") do
      diff = SiteSync::Ledger.diff({}, { DOC => STATE })

      assert_empty diff[:deleted], "the banner reports 113 deletions the setting just excluded"
    end
  end

  test "published still sees them in the drift check" do
    with_mode("published") do
      diff = SiteSync::Ledger.diff({}, { DOC => STATE })

      assert_includes diff[:deleted], DOC
    end
  end

  test "a user's own documentation is not Roe's" do
    assert SiteSync::Ledger.roe_docs_path?("documentation/roe/guide.md")
    assert_not SiteSync::Ledger.roe_docs_path?("documentation/mine/guide.md"),
      "only Roe's bundled directory is safe to remove without asking"
  end
end
