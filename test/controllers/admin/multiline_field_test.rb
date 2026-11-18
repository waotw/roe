# frozen_string_literal: true

require "test_helper"

# A value with lines is drawn as a textarea when the editor opens, and saving
# it writes it back with its lines (a |- block), not folded onto one.
class Admin::MultilineFieldTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(create(:user))
    @post = create(:post, metadata: { "title" => "Quoted", "status" => "draft",
                                      "subtitle" => "On *Moby Dick*\nand more",
                                      "pullquote" => "_the quote_\n— benjamin welch",
                                      "location" => "Chicago" })
    FileUtils.mkdir_p(File.dirname(@post.file_path))
    File.write(@post.file_path, "---\n#{Post.format_metadata_yaml(@post.metadata.dup)}\n---\nBody.\n")
  end

  teardown { FileUtils.rm_f(@post.file_path) }

  test "a value with lines opens as a textarea, a one-line value as an input" do
    get edit_admin_post_path(@post)
    assert_response :success

    assert_select "textarea[data-metadata-field=pullquote][data-multiline]", text: /_the quote_\n— benjamin welch/
    assert_select "textarea[data-metadata-field=subtitle][data-multiline]", text: /On \*Moby Dick\*\nand more/
    assert_select "input[type=text][data-metadata-field=location][data-multiline]"
    assert_select "input[type=text][data-metadata-field=title]:not([data-multiline])"
    assert_select "[data-controller~=multiline-field]"
  end

  test "saving keeps the lines" do
    yaml = "title: \"Quoted\"\nstatus: \"draft\"\npullquote: |-\n  _the quote_\n  — benjamin welch\n"
    patch admin_post_path(@post), params: { metadata: yaml, content: "Body." }

    written = File.read(@post.file_path)
    assert_includes written, "pullquote: |-\n  _the quote_\n  — benjamin welch"
    assert_equal "_the quote_\n— benjamin welch", @post.reload.metadata["pullquote"]
  end
end
