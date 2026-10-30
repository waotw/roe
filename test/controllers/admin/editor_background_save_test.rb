# frozen_string_literal: true

require "test_helper"

# The content editor saves in the background (editor_background_save.js) and
# keeps the writer's place. These check what the server tells it back
# (EditorSave): when to leave the page alone, when to send a fresh metadata
# panel, and when the page has to load after all.
class EditorBackgroundSaveTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Accept" => "application/json" }.freeze

  setup do
    sign_in_as(create(:user))
    @files = []
  end

  teardown { @files.each { |f| FileUtils.rm_f(f) } }

  def page_with(yaml)
    file = File.join(RoeSitePaths::SITE_PATH, "pages", "background-save-#{SecureRandom.hex(4)}.md")
    File.write(file, "---\n#{yaml}---\nBody.\n")
    @files << file
    ContentSync.sync_file(file)
    Page.find_by!(file_path: RoeSitePaths.normalize(file))
  end

  def product_with(yaml)
    rel = "products/background-save-#{SecureRandom.hex(4)}.md"
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, "products"))
    File.write(File.join(RoeSitePaths::SITE_PATH, rel), "---\n#{yaml}---\nBody.\n")
    @files << File.join(RoeSitePaths::SITE_PATH, rel)
    ContentSync.sync_file(File.join(RoeSitePaths::SITE_PATH, rel))
    Product.find_by!(file_path: rel)
  end

  def reply = JSON.parse(response.body)

  # What the metadata panel sends for a page: tags already a list, as the
  # file will have them.
  CANONICAL_DRAFT = "title: \"Background\"\nstatus: \"draft\"\ntags: []\n"

  test "a plain save answers in JSON, writes the file and leaves the page alone" do
    page = page_with(CANONICAL_DRAFT)

    patch admin_page_path(page), params: { metadata: CANONICAL_DRAFT, content: "New body." }, headers: JSON_HEADERS

    assert_response :success
    assert_equal true, reply["saved"]
    assert_equal false, reply["reload"]
    assert_nil reply["metadata_html"], "nothing in the file differs from what the panel sent"
    assert_includes File.read(page.reload.file_path), "New body."
    assert_nil flash[:notice]
  end

  # Roe tidied what was sent (tags written as a list), so the panel the
  # writer sees is no longer what's in the file. The server sends the panel
  # as the edit page would draw it.
  test "when Roe changes the metadata on the way in, the answer carries the panel" do
    page = page_with(CANONICAL_DRAFT)

    patch admin_page_path(page), params: { metadata: "title: \"Background\"\nstatus: \"draft\"\ntags: \"one, two\"\n",
                                           content: "Body." }, headers: JSON_HEADERS

    assert_equal false, reply["reload"]
    html = reply["metadata_html"]
    assert_includes html, 'id="metadata-container"'
    assert_includes html, 'data-controller="metadata-editor'
    assert_match(/data-metadata-field="tags"[^>]*value="one, two"|value="one, two"[^>]*data-metadata-field="tags"/, html,
                 "the panel shows the tags as saved")
  end

  test "the answer carries the saved address for the changed-live-URL prompt" do
    product = product_with("title: \"Poster\"\nstatus: \"draft\"\nprice: 10\ntags: []\n")

    patch admin_product_path(product),
          params: { metadata: "title: \"Poster\"\nstatus: \"draft\"\nprice: 10\ntags: []\nurl_name: \"big-poster\"\n", content: "Body." },
          headers: JSON_HEADERS

    assert_equal false, reply["reload"]
    assert_equal "big-poster", reply["url_name"]
  end

  # Publishing changes the buttons, the View link and shows a notice — more
  # than the editor redraws — so the page loads, with the notice waiting.
  test "publishing asks for the page, with the notice kept for it" do
    page = page_with(CANONICAL_DRAFT)

    patch admin_page_path(page), params: { metadata: CANONICAL_DRAFT.sub("draft", "published"), content: "Body." },
                                 headers: JSON_HEADERS

    assert_equal true, reply["reload"]
    assert_equal edit_admin_page_path(page), reply["url"]

    get reply["url"]
    assert_match "Page published", response.body
  end

  test "any status change asks for the page" do
    page = page_with(CANONICAL_DRAFT)

    patch admin_page_path(page), params: { metadata: CANONICAL_DRAFT.sub("draft", "unlisted"), content: "Body." },
                                 headers: JSON_HEADERS

    assert_equal true, reply["reload"]
  end

  test "a YAML warning asks for the page, so the warning shows" do
    page = page_with(CANONICAL_DRAFT)

    patch admin_page_path(page), params: { metadata: "title: [unclosed", content: "Body." }, headers: JSON_HEADERS

    assert_equal true, reply["reload"]
    assert_match(/YAML warning/, flash[:warning])
  end

  # Turbo and anything else posting the form as HTML get what they always got.
  test "an ordinary form post still redirects to the editor" do
    page = page_with(CANONICAL_DRAFT)

    patch admin_page_path(page), params: { metadata: CANONICAL_DRAFT, content: "Body." }

    assert_redirected_to edit_admin_page_path(page)
  end
end
