# frozen_string_literal: true

require "test_helper"

# Deletions and edits are different questions, so the pause screen asks them
# separately. The old copy told everyone "these files changed on both sides",
# which for a deletion isn't true — it was deleted on one side and still exists
# on the other.
class Admin::SiteSyncConflictCopyTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }
  teardown { Rails.cache.delete(SiteSyncTransferJob::STATUS_CACHE_KEY) }

  def entry = { "size" => 10, "mtime" => 1_700_000_000 }

  def paused_with(conflicts)
    Rails.cache.write(SiteSyncTransferJob::STATUS_CACHE_KEY,
      { state: :conflicts, kind: :sync, conflicts: conflicts }, expires_in: 1.hour)
    get admin_site_sync_path
  end

  def deletion(path, gone_from:)
    { "path" => path, "type" => gone_from == "live" ? "edit_delete" : "delete_edit",
      "local" => (entry if gone_from == "live"), "peer" => (entry if gone_from == "local"),
      "newer" => gone_from == "live" ? "local" : "live" }
  end

  def edit(path)
    { "path" => path, "type" => "edit_edit", "local" => entry, "peer" => entry, "newer" => "local" }
  end

  test "a deletion is described as a deletion, not as a change on both sides" do
    paused_with([ deletion("posts/a.md", gone_from: "live") ])

    assert_match(/paused —\s*1 deletion/, response.body)
    assert_match "This file was deleted on live", response.body
    assert_no_match(/changed on <strong>both<\/strong>/, response.body)
  end

  test "the buttons say Keep and Delete" do
    paused_with([ deletion("posts/a.md", gone_from: "live") ])

    assert_match(/>\s*Keep\s*</, response.body)
    assert_match(/>\s*Delete\s*</, response.body)
    assert_no_match "Keep mine", response.body
    assert_no_match "keeping live's side DELETES", response.body
  end

  # Clicking straight through must never destroy anything.
  test "Keep is the default" do
    paused_with([ deletion("posts/a.md", gone_from: "live") ])
    form = response.body[/posts\/a\.md.*?<\/div>\s*<\/div>/m]

    assert_match(/value="local" checked/, form,
      "the file only exists locally, so Keep must be pre-selected")
  end

  test "the copy names which side lost the file" do
    paused_with([ deletion("posts/a.md", gone_from: "live") ])
    assert_match(/deleted on <strong>live<\/strong> but remain on <strong>local<\/strong>/, response.body)

    paused_with([ deletion("posts/b.md", gone_from: "local") ])
    assert_match(/deleted on <strong>local<\/strong> but remain on <strong>live<\/strong>/, response.body)
  end

  test "a mixed batch is split, deletions first" do
    paused_with([ edit("posts/edited.md"), deletion("posts/gone.md", gone_from: "live") ])

    assert_match(/1 deletion and 1 conflict/, response.body)
    assert response.body.index("posts/gone.md") < response.body.index("posts/edited.md"),
      "deletions destroy something, so they're asked first"
    assert_match "This file was deleted on live", response.body
    assert_match "edited on both sides", response.body
  end

  # Most-recent is meaningless for a deletion — there's only one side.
  test "resolve-all-by-most-recent is only offered when there's an edit to judge" do
    paused_with([ deletion("posts/a.md", gone_from: "live") ])
    assert_no_match "RESOLVE ALL BY MOST-RECENT", response.body

    paused_with([ edit("posts/b.md") ])
    assert_match "RESOLVE ALL BY MOST-RECENT", response.body
  end

  test "an edit-only pause keeps its original wording" do
    paused_with([ edit("posts/b.md") ])

    assert_match(/paused —\s*1 conflict/, response.body)
    assert_match(/changed on <strong>both<\/strong>/, response.body)
    assert_no_match "was deleted on", response.body
  end
end
