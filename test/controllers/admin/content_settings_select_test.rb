require "test_helper"

# The Roe-documentation setting saved correctly but never showed its saved
# value: the config editor flattened only a named list of nested keys, and
# `docs` wasn't on it. The select fell back to its blank "Select..." option
# every time — including right after a save, which reads as the save being
# ignored.
class ContentSettingsSelectTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    @file = SiteConfig::CONTENT_FILE
    @original = File.exist?(@file) ? File.read(@file) : nil
  end

  teardown do
    @original ? File.write(@file, @original) : FileUtils.rm_f(@file)
    SiteConfig.sync_from_file("content") rescue nil
  end

  def write_content(yaml)
    FileUtils.mkdir_p(File.dirname(@file))
    File.write(@file, yaml)
  end

  # The selected option is the stored one, not the placeholder.
  test "a saved nested setting shows as selected" do
    write_content("docs:\n  roe: \"searchable\"\n")

    get admin_edit_content_config_path

    assert_response :success
    assert_select "select[name='config_fields[docs.roe]'] option[value='searchable'][selected]"
    assert_select "select[name='config_fields[docs.roe]'] option[value=''][selected]", 0,
      "the blank placeholder must not win over a stored value"
  end

  test "published shows as selected too" do
    write_content("docs:\n  roe: \"published\"\n")

    get admin_edit_content_config_path

    assert_select "select[name='config_fields[docs.roe]'] option[value='published'][selected]"
  end

  # Unset is "local", not "nothing chosen".
  test "an unset setting sits at its default rather than the placeholder" do
    write_content("soft_line_breaks: true\n")

    get admin_edit_content_config_path

    assert_response :success
    assert_select "select[name='config_fields[docs.roe]'] option[value='local'][selected]"
  end

  # The allowlist covered `search`, so these already worked — they're here so a
  # future change to the flattener can't quietly break them.
  test "the settings that already flattened still do" do
    write_content("search:\n  all_pages: true\ndocs:\n  roe: \"local\"\n")

    get admin_edit_content_config_path

    assert_response :success
    assert_select "input[name='config_fields[search.all_pages]'][checked]"
  end
end
