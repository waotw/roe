# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "config_image_path passes absolute media paths through unchanged" do
    assert_equal "/media/images/logo.svg", config_image_path("/media/images/logo.svg")
  end

  test "config_image_path passes absolute system paths through unchanged" do
    assert_equal "/system/images/logo.svg", config_image_path("/system/images/logo.svg")
  end

  test "config_image_path passes full URLs through unchanged" do
    assert_equal "https://cdn.example.com/logo.png", config_image_path("https://cdn.example.com/logo.png")
  end

  test "config_image_path resolves a bare filename under /system/images" do
    assert_equal system_image_path("logo.svg"), config_image_path("logo.svg")
  end

  test "config_image_path returns nil for blank or none" do
    assert_nil config_image_path("")
    assert_nil config_image_path(nil)
    assert_nil config_image_path("none")
  end
end
