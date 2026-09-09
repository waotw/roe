# frozen_string_literal: true

require "test_helper"

# Episode/track/chapter numbers and url_names are expected to be unique, but a
# clash is a warning rather than an error — Roe tells the writer and lets them
# decide. Numbers are scoped: episode 1 of two different shows is not a clash.
class PostUniqueFieldsTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def write_post(name, extra = {})
    meta = { "title" => name.tr("-", " "), "url_name" => name, "status" => "published" }.merge(extra)
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "x")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    slug
  end

  def conflict(**kwargs)
    Post.conflicting_post(**kwargs)
  end

  test "a repeated episode number within the same podcast is a conflict" do
    write_post("uf-ep1", "post_type" => "podcast", "podcast" => "showa", "episode_number" => "1")

    found = conflict(field: "episode_number", value: "1", scopes: { "podcast" => "showa" })

    assert_not_nil found
    assert_equal "uf ep1", found.title
  end

  test "the same number in a different podcast is not a conflict" do
    write_post("uf-ep-a", "post_type" => "podcast", "podcast" => "showa", "episode_number" => "1")

    assert_nil conflict(field: "episode_number", value: "1", scopes: { "podcast" => "showb" }),
      "episode 1 of another show is a different episode 1"
  end

  test "track numbers are scoped to their release" do
    write_post("uf-tr", "post_type" => "music", "release" => "ep-one", "track_number" => "2")

    assert_not_nil conflict(field: "track_number", value: "2", scopes: { "release" => "ep-one" })
    assert_nil conflict(field: "track_number", value: "2", scopes: { "release" => "ep-two" })
  end

  test "unscoped items still see each other" do
    write_post("uf-loose", "post_type" => "music", "track_number" => "5")

    assert_not_nil conflict(field: "track_number", value: "5", scopes: {}),
      "two loose tracks with no release should still compare"
  end

  # YAML picks the type: `episode_number: 1` is an Integer, `"1"` a String, and
  # SQLite doesn't compare those equal. Comparing as text is what makes a
  # hand-written episode and one Roe created see each other at all.
  test "a number written unquoted still clashes with a quoted one" do
    path = File.join(RoeSitePaths::SITE_POSTS_PATH, "uf-int.md")
    File.write(path, "---\ntitle: \"Unquoted\"\nurl_name: uf-int\nstatus: published\n" \
                     "post_type: podcast\npodcast: showa\nepisode_number: 3\n---\nx\n")
    @created << path
    ContentSync.sync_file(path)

    assert_not_nil conflict(field: "episode_number", value: "3", scopes: { "podcast" => "showa" }),
      "an Integer in the file must still match the string the form sends"
  end

  # --- seasons -------------------------------------------------------------

  test "the same episode number in a different season is not a conflict" do
    write_post("uf-s1e1", "post_type" => "podcast", "podcast" => "showa",
                          "season" => "1", "episode_number" => "1")

    assert_nil conflict(field: "episode_number", value: "1",
                        scopes: { "podcast" => "showa", "season" => "2" }),
      "episode 1 of season 2 is a different episode 1"
    assert_not_nil conflict(field: "episode_number", value: "1",
                            scopes: { "podcast" => "showa", "season" => "1" })
  end

  test "an episode with no season doesn't clash with a seasoned one" do
    write_post("uf-seasonless", "post_type" => "podcast", "podcast" => "showa",
                                "episode_number" => "1")

    assert_nil conflict(field: "episode_number", value: "1",
                        scopes: { "podcast" => "showa", "season" => "1" }),
      "a seasonless episode 1 and season 1's episode 1 are different episodes"
    assert_not_nil conflict(field: "episode_number", value: "1",
                            scopes: { "podcast" => "showa", "season" => "" }),
      "two seasonless episode 1s do clash"
  end

  test "url_name is unique site-wide, with no scope" do
    write_post("uf-slug")

    assert_not_nil conflict(field: "url_name", value: "uf-slug")
  end

  test "a post doesn't flag itself" do
    write_post("uf-self", "post_type" => "podcast", "podcast" => "showa", "episode_number" => "7")

    assert_nil conflict(field: "episode_number", value: "7", scopes: { "podcast" => "showa" },
                        exclude_url_name: "uf-self")
  end

  test "a blank value and an unknown field are never conflicts" do
    write_post("uf-blank", "post_type" => "podcast", "podcast" => "showa", "episode_number" => "9")

    assert_nil conflict(field: "episode_number", value: "")
    assert_nil conflict(field: "episode_number", value: "   ")
    assert_nil conflict(field: "status", value: "published"),
      "only whitelisted fields are checked — the name is interpolated into SQL"
  end
end
