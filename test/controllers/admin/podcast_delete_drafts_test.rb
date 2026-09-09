require "test_helper"

# Deleting a podcast show from podcast.yml can optionally take its DRAFT
# episodes with it. Published episodes are always kept (removed by hand).
class Admin::PodcastDeleteDraftsTest < ActionDispatch::IntegrationTest
  PODCAST_YML = PodcastConfigSeeder::PODCAST_YML
  POSTS_DIR   = RoeSitePaths::SITE_POSTS_PATH

  setup do
    sign_in_as(User.take)
    @podcast_yml_backup = File.exist?(PODCAST_YML) ? File.read(PODCAST_YML) : :absent
    @created_files = []
  end

  teardown do
    if @podcast_yml_backup == :absent
      File.delete(PODCAST_YML) if File.exist?(PODCAST_YML)
    else
      File.write(PODCAST_YML, @podcast_yml_backup)
    end
    SiteConfig.reload!("features/podcast") rescue nil
    @created_files.each { |f| File.delete(f) if File.exist?(f) }
  end

  def write_podcast(shows)
    FileUtils.mkdir_p(File.dirname(PODCAST_YML))
    File.write(PODCAST_YML, shows.to_yaml.sub(/\A---\s*\n/, ""))
    SiteConfig.reload!("features/podcast")
  end

  def make_episode(slug, podcast:, status:)
    FileUtils.mkdir_p(POSTS_DIR)
    path = File.join(POSTS_DIR, "#{slug}.md")
    meta = {
      "title" => slug.tr("-", " "), "url_name" => slug, "post_type" => "podcast",
      "podcast" => podcast, "status" => status, "date" => "2026-01-01",
      "audio" => "https://example.com/#{slug}.mp3"
    }
    File.write(path, "---\n#{Post.format_metadata_yaml(meta)}\n---\nbody\n")
    @created_files << path
    Post.create_or_update_from_file(path)
    path
  end

  test "delete_drafts removes the show's draft episodes but keeps published + other shows'" do
    write_podcast(
      "all-songs-considered" => { "title" => "All Songs Considered", "link" => "" },
      "keep-me"              => { "title" => "Keep Me", "link" => "" }
    )
    d1    = make_episode("asc-draft-1", podcast: "all-songs-considered", status: "draft")
    d2    = make_episode("asc-draft-2", podcast: "all-songs-considered", status: "draft")
    pub   = make_episode("asc-published", podcast: "all-songs-considered", status: "published")
    other = make_episode("keep-draft-1", podcast: "keep-me", status: "draft")

    delete delete_podcast_entry_admin_configs_path(key: "all-songs-considered", delete_drafts: 1)

    assert_not File.exist?(d1), "draft file deleted"
    assert_not File.exist?(d2), "draft file deleted"
    assert File.exist?(pub), "published episode kept"
    assert File.exist?(other), "other show's drafts untouched"

    assert_not Post.exists?([ "json_extract(metadata, '$.url_name') = ?", "asc-draft-1" ]), "draft record removed"
    assert Post.exists?([ "json_extract(metadata, '$.url_name') = ?", "asc-published" ]), "published record kept"
    assert Post.exists?([ "json_extract(metadata, '$.url_name') = ?", "keep-draft-1" ]), "other show's record kept"
  end

  test "deleting without delete_drafts keeps the draft episodes" do
    write_podcast(
      "all-songs-considered" => { "title" => "All Songs Considered", "link" => "" },
      "keep"                 => { "title" => "Keep", "link" => "" }
    )
    d1 = make_episode("asc-d1", podcast: "all-songs-considered", status: "draft")

    delete delete_podcast_entry_admin_configs_path(key: "all-songs-considered")

    assert File.exist?(d1), "draft kept when not opted in"
    assert Post.exists?([ "json_extract(metadata, '$.url_name') = ?", "asc-d1" ])
  end

  test "the danger zone offers the draft-delete when a show has drafts" do
    write_podcast("all-songs-considered" => { "title" => "All Songs Considered", "link" => "" })
    make_episode("asc-d1", podcast: "all-songs-considered", status: "draft")
    make_episode("asc-pub", podcast: "all-songs-considered", status: "published")

    get admin_edit_podcast_config_path
    assert_response :success
    assert_select "form[action=?]", delete_podcast_entry_admin_configs_path(key: "all-songs-considered", delete_drafts: 1)
    assert_match "1 draft episode", response.body
  end
end
