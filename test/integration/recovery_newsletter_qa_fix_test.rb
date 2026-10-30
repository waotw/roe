
require "test_helper"
class RecoveryAndNewsletterQAFixTest < ActionDispatch::IntegrationTest
  test "recover-account GET renders the page in password mode (no missing-template 500)" do
    SiteFeature.stubs(:member_passwords_enabled?).returns(true)
    unless Page.where("json_extract(metadata, '$.url_name') = ?", "recover-account").exists?
      create(:page, content: "Reset your password with a recovery code.",
             metadata: { "title" => "Recover account", "url_name" => "recover-account", "status" => "published" })
    end
    get "/recover-account"
    assert_response :success
  end

  test "account page hides newsletter section when newsletter feature is off" do
    SiteFeature.stubs(:newsletters_enabled?).returns(false)
    m = create(:member, :active, email: "n@example.com", name: "N")
    sign_in_member(m)
    get "/account"
    assert_response :success
    assert_not_includes response.body, "account-newsletter", "newsletter block hidden when feature off"
  end

  test "account page shows newsletter section when newsletter feature is on" do
    SiteFeature.stubs(:newsletters_enabled?).returns(true)
    m = create(:member, :active, email: "n2@example.com", name: "N2")
    sign_in_member(m)
    get "/account"
    assert_response :success
    assert_includes response.body, "account-newsletter"
  end
end
