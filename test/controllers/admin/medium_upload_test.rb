# frozen_string_literal: true

require "test_helper"

class Admin::MediumUploadTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, "media", "images"))
  end

  def teardown
    %w[images audio video].each do |t|
      Dir.glob(File.join(RoeSitePaths::SITE_PATH, "media", t, "mu-*")).each { |f| File.delete(f) rescue nil }
    end
  end

  def upload(filename, content_type, bytes = "x")
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    file.binmode
    file.write(bytes)
    file.rewind
    uploaded = Rack::Test::UploadedFile.new(file.path, content_type, original_filename: filename)
    post admin_medium_index_path, params: { files: [ uploaded ] }, headers: { "Accept" => "application/json" }
    JSON.parse(response.body)
  ensure
    file&.close!
  end

  test "supported image upload returns the rendered card as JSON" do
    data = upload("mu-pic.png", "image/png")

    assert data["success"], data.inspect
    assert_includes data["card_html"], "mu-pic.png"
    assert_includes data["card_html"], 'data-media-filter-target="item"'
    assert Medium.exists?(file_path: "/media/images/mu-pic.png")
  end

  test "card endpoint re-renders a media card as JSON with a pending flag" do
    ImageVariantGenerator.stubs(:available?).returns(false)
    medium = Medium.create!(file_path: "/media/images/mu-card.png", media_type: "images", uploaded_at: Time.current)

    get card_admin_medium_path(medium), headers: { "Accept" => "application/json" }

    assert_response :success
    data = JSON.parse(response.body)
    assert_includes data["card_html"], "mu-card.png"
    assert_equal false, data["pending"]
  end

  test "unsupported format is rejected with a clear error, not silently" do
    data = upload("mu-file.xyz", "application/octet-stream")

    assert_not data["success"]
    assert_match(/unsupported/i, data["error"])
    assert_equal 0, Medium.count
  end

  test "tiff without image processing is rejected in web-friendly language (no libvips mention)" do
    ImageVariantGenerator.stubs(:available?).returns(false)

    data = upload("mu-scan.tiff", "image/tiff")

    assert_not data["success"]
    assert_match(/well supported on the web/i, data["error"])
    assert_no_match(/libvips|vips/i, data["error"])
    assert_equal 0, Medium.count
  end
end
