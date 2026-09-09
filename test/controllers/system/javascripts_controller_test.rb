require "test_helper"

class System::JavascriptsControllerTest < ActionDispatch::IntegrationTest
  test "serves the shipped site JS (search, gallery, checkout)" do
    %w[search gallery checkout].each do |name|
      get "/javascript/#{name}.js"
      assert_response :success, "#{name}.js should serve"
      assert_equal "application/javascript", response.media_type
    end
  end

  test "returns 404 for missing files" do
    get "/javascript/missing.js"
    assert_response :not_found
  end
end
