# frozen_string_literal: true

require "test_helper"

# The browse page's audience toggles. Filtering is client-side alongside search
# and sort, so the server's job is to hand each card the two facts the toggles
# read: what the file resolved to, and whether it's mixed.
class Admin::MediaAudienceFilterTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def medium(path)
    absolute = File.join(RoeSitePaths::SITE_PATH, path.delete_prefix("/"))
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "bytes")
    Medium.find_or_create_by!(file_path: path) { |m| m.media_type = "images" }
  end

  # Referenced from the body, not the image field. A featured image is public
  # whatever the record's audience — rendered above the paywall and published
  # as og:image — so it can't be used to mint a paid file.
  def content(model, audience:, path:)
    dir = model == Post ? "posts" : "pages"
    n = model.count
    model.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, dir, "c#{n}.md"),
      content: "Body. ![m](#{path})",
      metadata: { "title" => "C#{n}", "url_name" => "c#{n}", "status" => "published",
                  "audience" => audience }
    )
  end

  test "each card carries its resolved audience" do
    medium("/media/images/paid.jpg")
    content(Post, audience: "paid", path: "/media/images/paid.jpg")
    medium("/media/images/free.jpg")
    content(Post, audience: "everyone", path: "/media/images/free.jpg")

    get browse_admin_medium_index_path

    assert_response :success
    assert_select "[data-filename=?][data-audience=?]", "paid.jpg", "paid"
    assert_select "[data-filename=?][data-audience=?]", "free.jpg", "free"
  end

  # A mixed file resolves to FREE — public wins — so it can't be found by the
  # audience column alone. It needs its own flag, and it's the case the toggles
  # exist for: a file you meant to protect that something public also uses.
  test "a file used by both paid and free content is flagged mixed" do
    medium("/media/images/both.jpg")
    content(Post, audience: "paid", path: "/media/images/both.jpg")
    content(Page, audience: "everyone", path: "/media/images/both.jpg")

    get browse_admin_medium_index_path

    assert_select "[data-filename=?][data-audience=?]", "both.jpg", "free"
    assert_select "[data-filename=?][data-mixed=?]", "both.jpg", "true"
  end

  test "a plain paid file is not mixed" do
    medium("/media/images/only-paid.jpg")
    content(Post, audience: "paid", path: "/media/images/only-paid.jpg")

    get browse_admin_medium_index_path

    assert_select "[data-filename=?][data-mixed=?]", "only-paid.jpg", "false"
  end

  test "the toggles render on the results line" do
    get browse_admin_medium_index_path

    assert_select "[data-media-filter-target=?]", "paidToggle"
    assert_select "[data-media-filter-target=?]", "freeToggle"
    assert_select "[data-media-filter-target=?]", "audienceNote"
  end

  # The $ next to a usage is what tells you which reference is doing the
  # protecting — and on a mixed file, which one isn't.
  test "a paid reference is marked in Used in" do
    medium("/media/images/marked.jpg")
    content(Post, audience: "paid", path: "/media/images/marked.jpg")

    get browse_admin_medium_index_path

    assert_select "[title=?]", "Paid — this reference protects the file"
  end

  test "a free reference is not marked" do
    medium("/media/images/plain.jpg")
    content(Post, audience: "everyone", path: "/media/images/plain.jpg")

    get browse_admin_medium_index_path

    assert_select "[title=?]", "Paid — this reference protects the file", count: 0
  end
end
