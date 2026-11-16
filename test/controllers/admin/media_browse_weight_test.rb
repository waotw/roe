require "test_helper"

# The Media page renders every file at once, so each card is kept light:
# no full-size originals while a preview can be made, one shared rename
# form, and "Used in" fetched only for cards on screen.
class Admin::MediaBrowseWeightTest < ActionDispatch::IntegrationTest
  DIR = File.join(RoeSitePaths::SITE_PATH, "media", "images", "weight_test").freeze

  setup do
    sign_in_as(User.take)
    FileUtils.mkdir_p(DIR)
  end

  teardown do
    FileUtils.rm_rf(DIR)
    Medium.where("file_path LIKE ?", "/media/images/weight_test/%").destroy_all
  end

  def image(name, preview: nil)
    path = File.join(DIR, name)
    File.binwrite(path, "bytes")
    if preview
      variant = ImageVariantGenerator.variant_path_for(path, preview)
      FileUtils.mkdir_p(File.dirname(variant))
      File.binwrite(variant, "bytes")
    end
    Medium.create!(file_path: "/media/images/weight_test/#{name}", media_type: "images", variants_status: "pending")
  end

  def card_for(medium)
    css_select("[data-media-id='#{medium.id}'][data-media-filter-target]").first
  end

  test "an image with a preview shows the preview" do
    ImageVariantGenerator.stubs(:available?).returns(true)
    medium = image("ready.jpg", preview: :small)

    get browse_admin_medium_index_path
    img = card_for(medium).at_css("img")
    assert_equal "/media/images/weight_test/variants/ready-small.jpg", img["src"]
    assert_equal "lazy", img["loading"]
    assert_equal "false", card_for(medium)["data-variants-pending"]
  end

  test "an animated GIF's still thumb is its preview, not the GIF itself" do
    ImageVariantGenerator.stubs(:available?).returns(true)
    medium = image("moving.gif", preview: :thumb)

    get browse_admin_medium_index_path
    assert_equal "/media/images/weight_test/variants/moving-thumb.gif", card_for(medium).at_css("img")["src"]
  end

  test "an image with no preview yet shows a box and waits, never the original" do
    ImageVariantGenerator.stubs(:available?).returns(true)
    medium = image("new.jpg")

    get browse_admin_medium_index_path
    card = card_for(medium)
    assert_nil card.at_css("img"), "the original isn't loaded"
    assert_includes card.text, "preview…"
    assert_equal "true", card["data-variants-pending"]
  end

  test "with no way to make previews, the original is shown, lazily" do
    ImageVariantGenerator.stubs(:available?).returns(false)
    medium = image("plain.jpg")

    get browse_admin_medium_index_path
    img = card_for(medium).at_css("img")
    assert_equal medium.file_path, img["src"]
    assert_equal "lazy", img["loading"]
  end

  test "one rename form for the whole page, and each card carries what it needs" do
    ImageVariantGenerator.stubs(:available?).returns(false)
    a = image("a.jpg")
    image("b.jpg")

    get browse_admin_medium_index_path
    assert_select "template[data-media-rename-target=form] form", 1
    assert_select "[data-media-filter-target=item] form", 0
    assert_select "script", text: /startMediaRename/, count: 0

    container = card_for(a).at_css(".inline-rename-container")
    assert_equal "/admin/medium/#{a.id}/rename", container["data-rename-url"]
    assert_equal "a", container["data-name"]
    assert_equal ".jpg", container["data-extension"]
    assert_equal "dblclick->media-rename#start", container.at_css(".filename-display")["data-action"]
  end

  test "Used in is a placeholder on the page and arrives from usages" do
    ImageVariantGenerator.stubs(:available?).returns(false)
    medium = image("used.jpg")
    unused = image("lonely.jpg")
    create(:post, metadata: { "title" => "Holiday", "status" => "published" },
                  content: "![x](/media/images/weight_test/used.jpg)")
    MediaUsageIndex.invalidate! if MediaUsageIndex.respond_to?(:invalidate!)

    get browse_admin_medium_index_path
    assert_select "[data-usages-pending='#{medium.id}']", 1
    assert_equal "true", card_for(medium)["data-has-references"], "the Unused tab still knows"
    assert_includes card_for(unused).text, "Unused", "nothing to fetch for an unused file"

    get usages_admin_medium_index_path, params: { ids: [ medium.id ] }, as: :json
    html = response.parsed_body[medium.id.to_s]
    assert_includes html, "Used in:"
    assert_includes html, "Holiday"
  end

  test "a card fetched on its own has its Used in filled in" do
    ImageVariantGenerator.stubs(:available?).returns(false)
    medium = image("solo.jpg")
    create(:post, metadata: { "title" => "Solo post", "status" => "published" },
                  content: "![x](/media/images/weight_test/solo.jpg)")
    MediaUsageIndex.invalidate! if MediaUsageIndex.respond_to?(:invalidate!)

    get card_admin_medium_path(medium), as: :json
    assert_includes response.parsed_body["card_html"], "Solo post"
  end
end
