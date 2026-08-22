# frozen_string_literal: true

require "test_helper"

# The label column used to be a fixed w-32 (8rem), sized for the longest label
# anywhere in the editor — image_in_header, a post field. On a product or a
# page, where nothing comes close, that left a visible gap before every field;
# on a post it was actually 3px short.
#
# It's now sized per resource type, in `ch` — exact, because the labels are
# monospace.
class Admin::MetadataLabelColumnTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def column_for(body)
    body[/--metadata-label-width:\s*(\d+)ch/, 1]&.to_i
  end

  def longest_label(type)
    ContentMetadataSchema.fields_for(type).values.map { |c| c[:label].to_s.length }.max
  end

  # The pages controller reads file_path as-is, so it stores an absolute path
  # (products store one relative to the site root).
  def make_page
    path = File.join(RoeSitePaths::SITE_PATH, "pages", "about.md")
    FileUtils.mkdir_p(File.dirname(path))
    meta = { "title" => "About", "url_name" => "about", "status" => "draft" }
    File.write(path, "#{meta.to_yaml}---\nBody.\n")
    Page.create!(file_path: path, content: "Body.", metadata: meta)
  end

  test "the column is the longest label plus the colon" do
    get edit_admin_page_path(make_page)

    assert_response :success
    assert_equal longest_label("page") + 1, column_for(response.body),
      "one character per label character, plus the colon"
  end

  # The point of the change: a page's column is narrower than a post's, because
  # a page has no image_in_header.
  test "a resource type with shorter labels gets a narrower column" do
    assert_operator longest_label("page"), :<, longest_label("post"),
      "if this stops being true the test below proves nothing"

    get edit_admin_page_path(make_page)
    page_column = column_for(response.body)

    assert_operator page_column, :<, longest_label("post") + 1
  end

  test "the labels use the shared class rather than a fixed width" do
    get edit_admin_page_path(make_page)

    assert_select "label.metadata-label"
    assert_select "label.w-32", count: 0
  end
end
