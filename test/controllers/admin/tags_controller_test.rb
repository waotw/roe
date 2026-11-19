require "test_helper"

class Admin::TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @created = []
  end
  teardown { @created.each { |f| File.delete(f) if File.exist?(f) } }

  def make_post(name, tags)
    meta = { "title" => name, "url_name" => name, "status" => "draft",
             "post_type" => "article", "date" => "2024-01-01",
             "audience" => "everyone", "tags" => tags }
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "body")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
    Post.find_by("json_extract(metadata, '$.url_name') = ?", slug)
  end

  test "lists each tag with counts that link to the filtered list" do
    make_post("tc-one", %w[tc-lab])
    make_post("tc-two", %w[tc-lab])

    get admin_tags_path
    assert_response :success
    assert_select "turbo-frame#tag_manager"
    assert_select "[data-tag=?]", "tc-lab" do
      assert_select "a[href=?]", admin_posts_path(tag: "tc-lab"), text: "2"
    end
  end

  test "names unused tags" do
    TagList.add!("tc-interviews")

    get admin_tags_path
    assert_select "p", text: /tc-interviews\s+is unused\./
  end

  test "the Products column shows only with the store on" do
    make_post("tc-col", %w[tc-col])
    store = SiteConfig::FEATURES_PATH.join("store.yml")
    original = File.exist?(store) ? File.read(store) : nil

    File.delete(store) if File.exist?(store)
    get admin_tags_path
    assert_select "span", text: "Products", count: 0

    File.write(store, "enabled: true\n")
    get admin_tags_path
    assert_select "span", text: "Products"
  ensure
    original ? File.write(store, original) : FileUtils.rm_f(store)
  end

  test "add, rename and delete" do
    post admin_tags_path, params: { name: "tc-new" }
    assert_redirected_to admin_tags_path
    assert_includes TagList.names, "tc-new"

    post admin_tags_path, params: { name: "tc-new" }
    assert_response :unprocessable_entity

    item = make_post("tc-rn", %w[tc-musi])
    patch admin_rename_tag_path, params: { from: "tc-musi", to: "tc-music" }
    assert_redirected_to admin_tags_path
    assert_equal %w[tc-music], item.reload.tags

    delete admin_destroy_tag_path, params: { name: "tc-music" }
    assert_equal [], item.reload.tags
    assert_not_includes TagList.names, "tc-music"
  end

  test "renaming onto an existing tag asks before merging" do
    item = make_post("tc-mg", %w[tc-lab-noimage])
    make_post("tc-mg2", %w[tc-lab])

    patch admin_rename_tag_path, params: { from: "tc-lab-noimage", to: "tc-lab" }
    assert_redirected_to admin_tags_path(merge_from: "tc-lab-noimage", merge_to: "tc-lab")
    assert_equal %w[tc-lab-noimage], item.reload.tags, "nothing changes until confirmed"

    follow_redirect!
    assert_select "button", text: "MERGE INTO TC-LAB"

    patch admin_rename_tag_path, params: { from: "tc-lab-noimage", to: "tc-lab", merge: "1" }
    assert_equal %w[tc-lab], item.reload.tags
  end

  test "bulk tags adds and removes across the selection" do
    a = make_post("tc-bulk-a", %w[tc-arts tc-keep])
    b = make_post("tc-bulk-b", %w[tc-arts])

    post bulk_tags_admin_posts_path, params: { ids: [ a.id, b.id ], add: [ "tc-music" ], remove: [ "tc-arts" ] }
    assert_response :redirect
    assert_equal %w[tc-keep tc-music], a.reload.tags
    assert_equal %w[tc-music], b.reload.tags
    assert_includes TagList.names, "tc-music"
    assert_not_includes TagList.names, "tc-arts"
  end

  test "the posts list filters by tag and offers the TAGS menu" do
    make_post("tc-filter-in", %w[tc-only])
    make_post("tc-filter-out", %w[tc-other])

    get admin_posts_path(tag: "tc-only")
    assert_response :success
    assert_select "code", text: "tc-only"
    assert_select "a", text: "tc-filter-in"
    assert_select "a", text: "tc-filter-out", count: 0
    assert_select "[data-controller~=?]", "bulk-tags"
    assert_select "form[action=?]", bulk_tags_admin_posts_path
  end

  test "saving Settings → Content keeps the tag list" do
    make_post("tc-settings", %w[tc-kept])

    patch admin_content_config_path, params: { content: "soft_line_breaks: true\n" }
    assert_includes TagList.names, "tc-kept"
  end

  test "the posts list has each post's tags as filter links for search to reveal" do
    make_post("tc-hits", %w[tc-hit])

    get admin_posts_path
    assert_select "[data-controller~=?]", "tag-hits"
    assert_select "[data-tag-hits-target=hits] a[href=?][data-tag=?]", admin_posts_path(tag: "tc-hit"), "tc-hit"
  end

  test "bulk tags goes back to the list, even after a visit to a members-only page" do
    a = make_post("tc-back", %w[tc-back])
    get "/account" # signed out as a member, so this stores /account to return to

    post bulk_tags_admin_posts_path, params: { ids: [ a.id ], remove: [ "tc-back" ] },
         headers: { "HTTP_REFERER" => "http://www.example.com/admin/posts?tag=tc-back" }
    assert_redirected_to "http://www.example.com/admin/posts?tag=tc-back"
  end

  test "the products list has a selection with the TAGS menu" do
    get admin_products_path
    assert_response :success
    assert_select "[data-controller~=?]", "bulk-select"
    assert_select "form[action=?]", bulk_tags_admin_products_path
  end

  test "a tag saved on a page from the editor joins the list" do
    path = File.join(RoeSitePaths::SITE_PATH, "pages", "tc-contact.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"TC Contact\"\nstatus: \"published\"\ntags: []\n---\nBody\n")
    @created << path
    ContentSync.sync_file(path)
    page = Page.find_by(file_path: RoeSitePaths.normalize(path)) || Page.find_by(file_path: path)

    patch admin_page_path(page), params: { metadata: "title: \"TC Contact\"\nstatus: \"published\"\ntags: [\"tc-contact\"]\n", content: "Body\n" }
    assert_includes TagList.names, "tc-contact"
    assert_equal 1, TagList.usage["tc-contact"][:pages]
  end

  test "the metadata editor draws the tags field with the site's tags" do
    item = make_post("tc-editor", %w[tc-ed])

    get edit_admin_post_path(item)
    assert_response :success
    assert_select "[data-controller=?]", "tag-field" do
      assert_select "input[type=hidden][data-metadata-field=tags][value=?]", "tc-ed"
    end
    assert_match "tc-ed", css_select("#metadata-container").first["data-metadata-editor-tag-options-value"]
  end
end
