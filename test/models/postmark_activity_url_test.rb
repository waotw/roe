require "test_helper"
class PostmarkActivityUrlTest < ActiveSupport::TestCase
  setup { @c = PostmarkConfig.current }

  test "activity_url_for builds the server events URL from the /server ID" do
    PostmarkService.stubs(:test_connection).with("tok").returns(success: true, server: { "ID" => 18843785 })
    assert_equal "https://account.postmarkapp.com/servers/18843785/streams/outbound/events",
                 @c.activity_url_for("tok")
  end

  test "activity_url_for is nil for a blank token" do
    assert_nil @c.activity_url_for("")
  end

  test "activity_url_for is nil when the API call has no ID" do
    PostmarkService.stubs(:test_connection).returns(success: false, error: "bad")
    assert_nil @c.activity_url_for("tok")
  end

  test "server_info_for returns the server name and activity url together" do
    PostmarkService.stubs(:test_connection).with("tok").returns(
      success: true, server: { "ID" => 18843785, "Name" => "My Site - Sandbox", "DeliveryType" => "Sandbox" }
    )
    info = @c.server_info_for("tok")
    assert_equal "My Site - Sandbox", info.name
    assert_equal "https://account.postmarkapp.com/servers/18843785/streams/outbound/events", info.activity_url
    assert_equal "Sandbox", info.delivery_type
  end

  test "server_info_for is nil for a blank token" do
    assert_nil @c.server_info_for("")
  end
end
