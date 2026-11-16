require "test_helper"

# The themes Roe ships share one heading format and the same sections, so the
# theme editor's table of contents reads the same in each. Only app/themes/ is
# checked; a site's own themes can do as they like.
class ThemeSectionsTest < ActiveSupport::TestCase
  SHIPPED = Dir.glob(Rails.root.join("app/themes/*.css")).sort

  test "parses sections and subsections with their line numbers" do
    css = <<~CSS
      /* ==== THEME INFO ====
         Roe Theme: Test
      */
      /* ==== CARDS ==== */
      .card {}
      /* ---- Card: aside ---- */
      /* Not a heading */
      /* --- Not one either --- */
    CSS

    headings = ThemeSections.parse(css)
    assert_equal [ [ 1, "THEME INFO", 1 ], [ 1, "CARDS", 4 ], [ 2, "Card: aside", 6 ] ],
                 headings.map { |h| [ h.level, h.name, h.line ] }
  end

  test "every shipped theme opens with THEME INFO and has the same headings in the same order" do
    assert SHIPPED.size >= 2
    lists = SHIPPED.to_h { |path| [ File.basename(path), ThemeSections.parse(File.read(path)).map { |h| [ h.level, h.name ] } ] }

    lists.each do |name, headings|
      assert_equal [ 1, "THEME INFO" ], headings.first, "#{name} doesn't open with THEME INFO"
      assert headings.select { |level, _| level == 1 }.all? { |_, n| n == n.upcase }, "#{name} has a section name that isn't uppercase"
    end
    first, *rest = lists.to_a
    rest.each do |name, headings|
      assert_equal first[1], headings, "#{name} and #{first[0]} have different headings"
    end
  end

  # The order follows the page: layout, then content, then the pieces inside
  # content, then features, with utilities and the site's own code last.
  test "shipped themes keep their sections in page order" do
    order = [
      "THEME INFO", "THEME VARIABLES", "DARK MODE", "BASE",
      "LAYOUT — SITE NAV", "LAYOUT — SITE ACTIONS", "LAYOUT — SITE SEARCH",
      "LAYOUT — SIDEBAR", "LAYOUT — FOOTER", "FLASH MESSAGES",
      "POST/PAGE GLOBAL", "POST/PAGE SINGLE",
      "COLLECTIONS", "COLLECTION PLAYLIST", "GALLERIES", "CARDS", "MEDIA PLAYERS",
      "BUTTONS", "FORMS", "SHARE",
      "PODCAST", "MEMBERS", "STORE — PRODUCT PAGE", "STORE — PRODUCT GRID", "DOCUMENTATION",
      "UTILITIES", "BREADCRUMBS", "CUSTOM CODE"
    ]
    SHIPPED.each do |path|
      sections = ThemeSections.parse(File.read(path)).select { |h| h.level == 1 }.map(&:name)
      assert_equal order, sections, File.basename(path)
    end
  end

  # A heading written almost in the format would silently drop out of the
  # table of contents.
  test "no shipped theme has a heading that's nearly in the format" do
    SHIPPED.each do |path|
      File.readlines(path).each_with_index do |text, i|
        next unless text.match?(%r{\A/\*\s*(={3,}|-{3,})})
        next if text.match?(ThemeSections::SECTION) || text.match?(ThemeSections::SUBSECTION)

        flunk "#{File.basename(path)}:#{i + 1} looks like a heading but isn't in the format: #{text.strip}"
      end
    end
  end
end
