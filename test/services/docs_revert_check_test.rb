require "test_helper"

# bin/sync-from-site holds back a site/ doc that is an exact copy of an older
# committed version of Roe's copy. These run against a throwaway git repo.
class DocsRevertCheckTest < ActiveSupport::TestCase
  APP_REL = "docs/roe".freeze

  setup do
    @root = Dir.mktmpdir("docs-revert")
    @repo = File.join(@root, "repo")
    @site = File.join(@root, "site")
    FileUtils.mkdir_p([ File.join(@repo, APP_REL), @site ])
    git "init", "-q"
    git "config", "user.email", "test@example.com"
    git "config", "user.name", "Test"
  end

  teardown { FileUtils.rm_rf(@root) }

  def git(*args)
    system("git", "-C", @repo, *args, out: File::NULL, err: File::NULL) || flunk("git #{args.join(' ')} failed")
  end

  def commit_doc(name, text)
    File.write(File.join(@repo, APP_REL, name), text)
    git "add", "."
    git "commit", "-q", "-m", "#{name}: #{text[0, 20]}"
  end

  def site_doc(name, text)
    File.write(File.join(@site, name), text)
  end

  def findings
    DocsRevertCheck.new(site_dir: @site, app_rel: APP_REL, repo: @repo).findings
  end

  test "a site doc identical to an older commit is held back, naming that commit" do
    commit_doc "a.md", "old wording\n"
    commit_doc "a.md", "new wording\n"
    site_doc "a.md", "old wording\n"

    found = findings
    assert_equal [ "a.md" ], found.map(&:rel)
    assert_match(/\A[0-9a-f]{7}\z/, found.first.commit)
  end

  test "a new edit, the current version, and a new file are all fine" do
    commit_doc "a.md", "old wording\n"
    commit_doc "a.md", "new wording\n"

    site_doc "a.md", "newer wording, being written\n"
    assert_empty findings, "an edit nobody committed before isn't going backwards"

    site_doc "a.md", "new wording\n"
    assert_empty findings, "the committed version itself is in sync"

    site_doc "b.md", "a doc Roe hasn't shipped yet\n"
    assert_empty findings
  end

  test "restoring lost text is forward, not backwards" do
    commit_doc "a.md", "old wording\n"
    commit_doc "a.md", "rewrite\n"
    commit_doc "a.md", "old wording\n" # a bad sync committed the old text again
    site_doc "a.md", "rewrite\n"        # and here it is being put back

    assert_empty findings
  end

  test "relative folder paths work the same as absolute ones" do
    commit_doc "a.md", "old wording\n"
    commit_doc "a.md", "new wording\n"
    site_doc "a.md", "old wording\n"

    Dir.chdir(@root) do
      found = DocsRevertCheck.new(site_dir: "site", app_rel: APP_REL, repo: "repo").findings
      assert_equal [ "a.md" ], found.map(&:rel)
    end
  end

  test "files in subfolders are checked too" do
    FileUtils.mkdir_p(File.join(@repo, APP_REL, "tutorials"))
    FileUtils.mkdir_p(File.join(@site, "tutorials"))
    commit_doc "tutorials/one.md", "v1\n"
    commit_doc "tutorials/one.md", "v2\n"
    site_doc "tutorials/one.md", "v1\n"

    assert_equal [ "tutorials/one.md" ], findings.map(&:rel)
  end
end
