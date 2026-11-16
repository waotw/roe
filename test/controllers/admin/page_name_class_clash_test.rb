require "test_helper"

# A page named like a layout part (`image`, `tags`) gets no page-<url_name>
# class (Page#name_class). The editor says so in its issues box, on the save
# that caused it (no reload) and on every load after.
class Admin::PageNameClassClashTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    sign_in_as(create(:user))
    @file = File.join(RoeSitePaths::SITE_PATH, "pages", "clash-#{SecureRandom.hex(4)}.md")
    File.write(@file, "---\ntitle: \"Clash\"\nstatus: \"draft\"\ntags: []\n---\nBody.\n")
    ContentSync.sync_file(@file)
    @page = Page.find_by!(file_path: RoeSitePaths.normalize(@file))
  end

  teardown { FileUtils.rm_f(@file) }

  test "saving a part's name as url_name shows the warning without a reload, and on every load after" do
    patch admin_page_path(@page), params: { metadata: "title: \"Clash\"\nstatus: \"draft\"\nurl_name: \"tags\"\ntags: []\n",
                                            content: "Body." }, headers: JSON_HEADERS
    reply = JSON.parse(response.body)
    assert_not reply["reload"]
    assert_match "page-tags", Nokogiri::HTML.fragment(reply["issues_html"]).at_css("#editor-issues [data-name-class-clash]").text

    get edit_admin_page_path(@page)
    assert_select "#editor-issues [data-name-class-clash]", 1
  end

  test "a page with an ordinary name shows no warning" do
    get edit_admin_page_path(@page)
    assert_select "[data-name-class-clash]", 0
  end
end
