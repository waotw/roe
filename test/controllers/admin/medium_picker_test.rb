# frozen_string_literal: true

require "test_helper"

# The media picker serves two callers. Opened from MEDIA it writes markdown into
# the document; opened from the gallery builder it hands its selection back
# there instead, because only the gallery builder writes gallery syntax.
#
# Which one it is comes from the request, so the button's label and action are
# decided in one place rather than patched in the browser after loading.
class Admin::MediumPickerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  test "opened from the media menu, it inserts into the document" do
    get picker_admin_medium_index_path(media_type: "images")

    assert_response :success
    assert_includes response.body, "Insert Selected"
    assert_includes response.body, "media-bulk-select#submitInsert"
    assert_not_includes response.body, "Add to Gallery"
  end

  # Copy URL needs exactly one selection and Gallery needs more than one, so
  # they share a slot and can never both apply.
  test "the images picker offers Gallery alongside Copy URL" do
    get picker_admin_medium_index_path(media_type: "images")

    assert_response :success
    assert_includes response.body, 'data-media-bulk-select-target="copyUrl"'
    assert_includes response.body, 'data-media-bulk-select-target="galleryButton"'
    assert_includes response.body, "media-bulk-select#submitGallery"
  end

  test "audio and video have nothing to make a gallery from" do
    %w[audio video].each do |type|
      get picker_admin_medium_index_path(media_type: type)

      assert_response :success
      assert_not_includes response.body, 'data-media-bulk-select-target="galleryButton"',
        "#{type} should not offer a gallery"
    end
  end

  test "opened for the gallery, it hands the selection back instead" do
    get picker_admin_medium_index_path(media_type: "images", for: "gallery")

    assert_response :success
    assert_includes response.body, "Add to Gallery"
    assert_includes response.body, "media-bulk-select#submitGallery"

    # Nothing here writes into the document, and the count-gated buttons would
    # only be a second way to do what the primary one already does.
    assert_not_includes response.body, "media-bulk-select#submitInsert"
    assert_not_includes response.body, 'data-media-bulk-select-target="copyUrl"'
    assert_not_includes response.body, 'data-media-bulk-select-target="galleryButton"'
  end

  # A one-image gallery is a legitimate thing to want, so the button that sends
  # images back isn't hidden until a second one is picked.
  test "the gallery button is not count-gated in gallery mode" do
    get picker_admin_medium_index_path(media_type: "images", for: "gallery")

    assert_response :success
    assert_no_match(/Add to Gallery.*?style="display: none;"/m, response.body)
  end
end
