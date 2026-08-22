# frozen_string_literal: true

require "test_helper"

# The docs sync uses rsync -c, so only genuinely-changed files are rewritten —
# without it every doc would look changed on every update, because extracting a
# release stamps fresh mtimes on all of them. The log then counted every file in
# the destination and announced all hundred-odd as updated, which made a
# correct, minimal sync look like it had rewritten the lot.
class DocSyncSummaryTest < ActiveSupport::TestCase
  def summary(output, total = 111)
    RoeUpdater::UpdateOrchestrator.send(:doc_sync_summary, output, total)
  end

  # rsync -i prints nothing for a file it leaves alone, so "no lines" is the
  # normal case for an update that didn't touch the docs.
  test "an update that changed no docs says so" do
    result = summary("")

    assert_includes result, "already current"
    assert_includes result, "111 files"
    assert_not_includes result, "updated"
  end

  test "only the changed files are counted" do
    output = <<~RSYNC
      >f.st...... 01-getting-started.md
      >f+++++++++ 09-new-page.md
    RSYNC

    assert_includes summary(output), "2 updated"
    assert_not_includes summary(output), "111 updated"
  end

  # Directory lines ride along with transfers and aren't docs.
  test "directory entries aren't counted as docs" do
    output = <<~RSYNC
      cd+++++++++ tutorials/
      >f+++++++++ tutorials/01-first.md
    RSYNC

    assert_includes summary(output), "1 updated"
  end

  test "removals are reported too" do
    output = <<~RSYNC
      >f.st...... 01-getting-started.md
      *deleting   06-removed.md
    RSYNC

    result = summary(output)

    assert_includes result, "1 updated"
    assert_includes result, "1 removed"
  end

  test "a removal on its own still counts as a change" do
    result = summary("*deleting   06-removed.md\n")

    assert_not_includes result, "already current"
    assert_includes result, "1 removed"
  end
end
