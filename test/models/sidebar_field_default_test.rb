require "test_helper"

# The field only exists to say the opposite of what the scope already does, so
# it defaults that way: unticked on a type the sidebar covers (you're adding it
# to hide), ticked on one it doesn't (you're adding it to show). Defaulting to
# current behaviour would make adding it a no-op.
class SidebarFieldDefaultTest < ActiveSupport::TestCase
  setup do
    @path = Sidebar.path
    FileUtils.mkdir_p(File.dirname(@path))
    @original = File.exist?(@path) ? File.binread(@path) : nil
  end

  teardown { @original ? File.write(@path, @original) : FileUtils.rm_f(@path) }

  def write_sidebar(scope) = File.write(@path, "---\nscope: #{scope}\n---\n\nSidebar\n")

  # Known but not offered: a field that can't do anything shouldn't be on the
  # Add Field menu, but a value someone already set mustn't degrade into a
  # custom text field just because they later deleted their sidebar.
  test "not offered when there's no sidebar, but still understood" do
    FileUtils.rm_f(@path)

    %w[post page product].each do |type|
      field = ContentMetadataSchema.fields_for(type)["show_sidebar"]

      assert field, "#{type}: an existing value still has to render as a checkbox"
      assert_equal :checkbox, field[:type], type
      assert_equal false, field[:available], "#{type}: shouldn't be offered in the menu"
      assert_match(/no sidebar/i, field[:hint], type)
    end
  end

  test "offered once a sidebar exists" do
    write_sidebar("all")

    assert_not_equal false, ContentMetadataSchema.fields_for("post")["show_sidebar"][:available]
  end

  test "a covered type defaults to unticked — you're adding it to hide" do
    write_sidebar("pages")

    field = ContentMetadataSchema.fields_for("page")["show_sidebar"]

    assert_equal :checkbox, field[:type]
    assert_equal "false", field[:default]
    assert_match(/already shows/i, field[:hint])
  end

  test "an uncovered type defaults to ticked — you're adding it to show" do
    write_sidebar("pages")

    field = ContentMetadataSchema.fields_for("post")["show_sidebar"]

    assert_equal "true", field[:default]
    assert_match(/doesn't show/i, field[:hint])
  end

  test "with no scope everything is covered, so everything defaults to unticked" do
    File.write(@path, "---\n---\n\nSidebar\n")

    %w[post page product].each do |type|
      assert_equal "false", ContentMetadataSchema.fields_for(type)["show_sidebar"][:default], type
    end
  end
end
