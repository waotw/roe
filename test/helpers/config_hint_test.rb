require "test_helper"

# Settings hints are written in the schema (Admin::ConfigsController) and were
# printed escaped, so the HTML in them showed on the page as visible source.
class ConfigHintTest < ActionView::TestCase
  include AdminHelper

  test "markdown becomes formatting" do
    assert_equal "<strong>local</strong> — kept here", config_hint("**local** — kept here")
  end

  # The hints already in the schema are written with tags, and they have to
  # keep working untouched — kramdown passes inline HTML straight through.
  test "hints already written with HTML still render" do
    assert_equal "<strong>local</strong> — kept here<br>and here",
      config_hint("<strong>local</strong> — kept here<br>and here")
  end

  test "links work, so a long hint can point at the docs instead" do
    assert_equal %(see <a href="/documentation/roe/x">the docs</a>),
      config_hint("see [the docs](/documentation/roe/x)")
  end

  test "code spans render" do
    assert_equal "set <code>docs.roe</code>", config_hint("set `docs.roe`")
  end

  # Hints render inside a <p>. Kramdown wraps its output in one too, and a
  # nested <p> makes the browser close the outer tag early — the hint loses
  # its styling and the layout shifts.
  test "the wrapping paragraph is stripped" do
    assert_not_includes config_hint("plain words"), "<p>"
  end

  test "script tags don't survive" do
    assert_not_includes config_hint("hi <script>alert(1)</script>"), "<script"
  end

  test "a blank hint renders nothing" do
    assert_nil config_hint(nil)
    assert_nil config_hint("")
  end

  # The real hint that prompted this, end to end. Reads the shipped schema
  # rather than a fixture, so it fails if that hint is ever rewritten into
  # something this helper mangles.
  test "the docs.roe hint formats" do
    hint = Admin::ConfigsController::CONTENT_CONFIG_SCHEMA
             .dig(:search, :fields, "docs.roe", :hint)
    assert hint.present?, "precondition — the docs.roe hint exists in the schema"

    rendered = config_hint(hint)

    # Asserts the shape, not the wording — this hint's copy is edited often and
    # a test pinned to a phrase would fail on every rewrite without a bug.
    assert_includes rendered, "<strong>", "bold should be applied, not printed"
    assert_not_includes rendered, "&lt;strong&gt;"
    assert_not_includes rendered, "**", "markdown bold should be consumed, not left in"
  end

  # Every hint the settings pages can render, checked in one go: none of them
  # should reach the page carrying escaped tags.
  test "no shipped hint renders escaped HTML" do
    checked = 0

    [ Admin::ConfigsController::SITE_CONFIG_SCHEMA,
      Admin::ConfigsController::CONTENT_CONFIG_SCHEMA,
      Admin::ConfigsController::SECURITY_CONFIG_SCHEMA ].each do |schema|
      schema.each_value do |section|
        next unless section.is_a?(Hash)

        section.fetch(:fields, {}).each do |key, field|
          next unless field.is_a?(Hash) && field[:hint].present?

          checked += 1
          assert_not_includes config_hint(field[:hint]), "&lt;",
            "#{key}'s hint reaches the page with an escaped tag in it"
        end
      end
    end

    assert_operator checked, :>, 20, "precondition — the sweep found the hints"
  end
end
