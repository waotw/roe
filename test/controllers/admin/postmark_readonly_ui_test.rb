require "test_helper"
class PostmarkReadonlyUiTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take); PostmarkConfig.delete_all }

  test "dev newsletters page renders a single read-only test panel, no key inputs" do
    get admin_edit_newsletters_config_path
    assert_response :success
    assert_select "[data-test=postmark-test-test]"
    assert_select "[data-test=postmark-webhook-status]"
    # No manual key input fields.
    assert_select "input[name='test[server_token]']", count: 0
    assert_select "input[type=submit][value='Save Test Keys']", count: 0
  end

  test "production newsletters page keeps both test and live panels" do
    Rails.env.stubs(:production?).returns(true)
    # Avoid the live /server calls hitting the network for the activity link.
    PostmarkConfig.any_instance.stubs(:activity_url_for).returns(nil)
    get admin_edit_newsletters_config_path
    assert_response :success
    assert_select "[data-test=postmark-test-test]"
    assert_select "[data-test=postmark-test-live]"
  end
end
