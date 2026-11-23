require "test_helper"
require_relative "../../video_test_helpers"

# The Media Browser's video window: DETAILS on a video card opens it
# (MediumController#details), its JUMP TO strip loads stills (#frame), and
# USE THIS FRAME / USE THIS IMAGE save at once (#poster).
class Admin::MediumVideoDetailsTest < ActionDispatch::IntegrationTest
  include VideoTestHelpers

  setup do
    sign_in_as(User.take)
    setup_video_dir
  end

  teardown { teardown_video_dir }

  def add_medium(web, type: "video")
    Medium.insert_all([ { file_path: web, media_type: type, variants_status: "complete",
                          created_at: Time.current, updated_at: Time.current } ])
    Medium.find_by!(file_path: web)
  end

  test "a video card has DETAILS beside its copy buttons; an image card doesn't" do
    video = add_medium(fake_variants("card.mp4"))
    image = add_medium("/media/images/card-test.jpg", type: "images")

    get card_admin_medium_path(video)
    html = Nokogiri::HTML(response.parsed_body["card_html"])
    details = html.at_css("[data-action='video-details#open']")
    assert details, "the card has a DETAILS button"
    assert_equal video.id.to_s, details["data-video-details-id-param"]
    assert_equal 2, details.parent.css("> div > button").size, "COPY URL and MARKDOWN LINK share the other half"

    get card_admin_medium_path(image)
    assert_nil Nokogiri::HTML(response.parsed_body["card_html"]).at_css("[data-action='video-details#open']")
  end

  test "the window shows the poster now, where it came from, and both ways to choose" do
    web = make_clip("window.mp4", seconds: 4, bitrate: "3M")
    make_all(web)
    medium = add_medium(web)
    add_medium("/media/images/a-still.jpg", type: "images")
    add_medium("/media/images/a-vector.svg", type: "images")

    get details_admin_medium_path(medium)
    assert_response :success
    page = Nokogiri::HTML(response.body)

    assert_match %r{\A/media/video/variants/window-poster\.jpg\?v=\d+\z}, page.at_css("[data-video-details-target=posterNow]")["src"]
    assert_match(/picked by Roe/, page.at_css("[data-video-details-target=caption]").text)
    assert_equal "/media/video/variants/window-720p.mp4", page.at_css("video")["src"], "plays the small web version"
    assert_equal 8, page.css("[data-video-details-target=jump]").size
    assert page.at_css("[data-video-details-target=useFrame]:not([disabled])")
    assert page.at_css("[data-video-details-target=pane][data-tab=image]")
    assert_equal %w[/media/images/a-still.jpg], page.css("[data-video-details-target=image]").map { |el| el["data-path"] },
                 "library images that can become a poster"
  end

  test "USE THIS FRAME saves at once and answers with the new poster" do
    web = make_clip("save.mp4", seconds: 4)
    make_all(web)
    medium = add_medium(web)

    post poster_admin_medium_path(medium), params: { at: 1.5 }, as: :json
    assert_response :success
    assert_match %r{\A/media/video/variants/save-poster\.jpg\?v=\d+\z}, response.parsed_body["poster"]
    assert_equal "Frame at 0:01 · chosen", response.parsed_body["caption"]
    assert_equal "frame", VideoVariantGenerator.current_manifest(web)["poster_from"]
  end

  test "an image that isn't in the media library is refused with a reason" do
    web = make_clip("refuse.mp4", seconds: 2)
    medium = add_medium(web)

    post poster_admin_medium_path(medium), params: { image: "/etc/passwd" }, as: :json
    assert_response :unprocessable_entity
    assert_match(/isn't an image in the media library/, response.parsed_body["error"])
  end

  test "a JUMP TO still comes back as a JPEG" do
    web = make_clip("still.mp4", seconds: 4)
    medium = add_medium(web)

    get frame_admin_medium_path(medium, at: 2)
    assert_response :success
    assert_equal "image/jpeg", response.media_type
  end

  test "only videos have a window" do
    image = add_medium("/media/images/not-a-video.jpg", type: "images")
    get details_admin_medium_path(image)
    assert_response :not_found
    post poster_admin_medium_path(image), params: { at: 1 }, as: :json
    assert_response :not_found
  end
end
