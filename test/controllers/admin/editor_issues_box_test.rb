# frozen_string_literal: true

require "test_helper"

# The issues box above the editor ("published but has issues") used to be
# drawn only on page load, and said "Save your changes to refresh this list"
# — but a save no longer reloads the page. Every background save now sends
# the box back (issues_html) and the editor swaps it in.
class EditorIssuesBoxTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    sign_in_as(create(:user))
    @file = File.join(RoeSitePaths::SITE_PATH, "pages", "issues-box-#{SecureRandom.hex(4)}.md")
  end

  teardown { FileUtils.rm_f(@file) }

  def page_with(yaml)
    File.write(@file, "---\n#{yaml}---\nBody.\n")
    ContentSync.sync_file(@file)
    Page.find_by!(file_path: RoeSitePaths.normalize(@file))
  end

  def issues = Nokogiri::HTML.fragment(JSON.parse(response.body)["issues_html"]).at_css("#editor-issues")

  test "the box comes back with every save: an issue appears, then goes" do
    yaml = "title: \"Box\"\nstatus: \"published\"\naudience: \"everyone\"\ntags: []\n"
    page = page_with(yaml)

    missing = yaml + "image: \"/media/images/zz-not-there.jpg\"\n"
    patch admin_page_path(page), params: { metadata: missing, content: "Body." }, headers: JSON_HEADERS
    assert_not JSON.parse(response.body)["reload"]
    assert_match "zz-not-there.jpg", issues.text

    patch admin_page_path(page), params: { metadata: yaml, content: "Body." }, headers: JSON_HEADERS
    assert_not JSON.parse(response.body)["reload"]
    assert_empty issues.text.strip, "fixed: the box is empty"
  end

  test "the edit page draws the box in the same wrapper, without the old refresh line" do
    page = page_with("title: \"Box\"\nstatus: \"draft\"\ntags: []\n")
    get edit_admin_page_path(page)

    assert_select "#editor-issues", 1
    assert_no_match "Save your changes to refresh this list", response.body
  end
end
