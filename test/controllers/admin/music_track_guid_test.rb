# frozen_string_literal: true

require "test_helper"

# A GUID is what a podcatcher dedupes on. Music tracks never got one — only
# `post_type: podcast` did — so a release published as a feed would have
# emitted empty guids and shown subscribers the whole album as new on every
# refresh. Generation runs on publish, through prepare_publish_metadata.
class Admin::MusicTrackGuidTest < ActiveSupport::TestCase
  def prepared(metadata, record: Post.new)
    Admin::PostsController.new.prepare_publish_metadata(record, metadata)
  end

  test "publishing a music track generates a guid" do
    result = prepared({ "post_type" => "music", "status" => "published", "title" => "Opening" })

    assert result["guid"].present?, "a published track needs a guid for the feed"
  end

  test "podcast episodes still get one" do
    result = prepared({ "post_type" => "podcast", "status" => "published", "title" => "Ep 1" })

    assert result["guid"].present?
  end

  # Nothing else ends up in a feed a client subscribes to, so nothing else
  # needs an immutable identifier following it around.
  test "other post types and drafts get none" do
    assert_nil prepared({ "post_type" => "article", "status" => "published" })["guid"]
    assert_nil prepared({ "post_type" => "music", "status" => "draft" })["guid"]
  end

  # The whole point of the GUID is that it never changes. An edit that clears
  # or rewrites it has to be refused, or every subscriber re-downloads.
  test "an existing guid survives an attempt to change it" do
    saved = Post.new(metadata: { "post_type" => "music", "status" => "published", "guid" => "keep-me" })
    saved.stubs(:persisted?).returns(true)

    changed = prepared({ "post_type" => "music", "status" => "published", "guid" => "new-value" }, record: saved)
    cleared = prepared({ "post_type" => "music", "status" => "published", "guid" => "" }, record: saved)

    assert_equal "keep-me", changed["guid"]
    assert_equal "keep-me", cleared["guid"]
  end

  test "two tracks don't share a guid" do
    a = prepared({ "post_type" => "music", "status" => "published", "title" => "A" })
    b = prepared({ "post_type" => "music", "status" => "published", "title" => "B" })

    assert_not_equal a["guid"], b["guid"]
  end
end
