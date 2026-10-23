# frozen_string_literal: true

require "test_helper"

# The metadata form's layout:
# - the url_name box sits outside fieldsContainer, which the controller
#   empties and rebuilds from the YAML on the way back from RAW (it lost the
#   box every time);
# - + Add Field sits in the header beside the Metadata toggle, not at the foot
#   of the list;
# - the form is in a white, bordered box like the editor's.
class Admin::MetadataEditorLayoutTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @path = File.join(RoeSitePaths::SITE_PATH, "posts", "mel-layout.md")
    File.write(@path, "---\ntitle: \"MEL\"\nstatus: \"draft\"\n---\n\nBody.\n")
    @post = Post.create!(file_path: @path, content: "Body.",
                         metadata: { "title" => "MEL", "url_name" => "mel-layout", "status" => "draft" })
  end

  teardown { File.delete(@path) if File.exist?(@path) }

  test "url_name is outside the rebuilt fields, and Add Field is in the header" do
    get edit_admin_post_path(@post)
    assert_response :success

    form = css_select("[data-metadata-editor-target='formView']").first
    assert form, "form view"
    assert_includes form["class"], "bg-white"
    assert_includes form["class"], "border-gray-300"

    fields = form.css("[data-metadata-editor-target='fieldsContainer']").first
    assert_includes form.text, "url_name:"
    assert_not_includes fields.text, "url_name:", "yamlToForm empties this container"
    assert_select "[data-metadata-editor-target='fieldsContainer'] .metadata-field-row", minimum: 1

    header = css_select("#metadata-container > div").first
    assert header.css("[data-action*='toggleMetadataSection']").any?
    add = header.css("[data-metadata-add-field]").first
    assert add, "Add Field is in the header"
    assert add.css("[data-metadata-editor-target='addFieldMenu']").any?, "with its menu"
    assert_empty form.css("[data-action*='toggleAddFieldMenu']"), "and not at the foot of the list"
    assert_select "[data-action*='toggleAddFieldMenu']", count: 1
  end
end
