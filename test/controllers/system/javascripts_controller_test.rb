require "test_helper"

class System::JavascriptsControllerTest < ActionDispatch::IntegrationTest
  test "serves search.js" do
    get "/javascript/search.js"
    assert_response :success
    assert_equal "application/javascript", response.media_type
    assert response.body.include?("site-search")
  end

  test "returns 404 for missing files" do
    get "/javascript/missing.js"
    assert_response :not_found
  end
end
