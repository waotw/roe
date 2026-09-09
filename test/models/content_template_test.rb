require "test_helper"
require "tmpdir"

# Guards the single-source-of-truth contract for new-content templates.
#
# The create actions (Admin::{Posts,Pages,Products}Controller#new/create) and
# the template editor (Admin::SettingsController) both read through
# ContentTemplate, whose files live in site/system/templates/ (with the install
# kit as fallback). The old per-controller load_*_template heredocs were removed
# so the two can never drift. These tests lock that in: if template_content
# stops preferring the site file, or frontmatter_for drops a required key, a new
# post/page/product could silently start from the wrong template.
class ContentTemplateTest < ActiveSupport::TestCase
  test "ships a canonical kit template for every content type" do
    ContentTemplate::TYPES.each do |type|
      kit = ContentTemplate::KIT_DIR.join("#{type}_template.md")
      assert kit.file?, "missing kit template (the fallback source): #{kit}"
    end
  end

  test "template_content prefers the install's site file over the kit" do
    Dir.mktmpdir do |tmp|
      with_template_dir(tmp) do
        ContentTemplate::TYPES.each do |type|
          File.write(File.join(tmp, "#{type}_template.md"), "SITE #{type}")
          assert_equal "SITE #{type}", ContentTemplate.template_content(type)
        end
      end
    end
  end

  test "template_content falls back to the kit when the install lacks the file" do
    Dir.mktmpdir do |tmp| # empty dir → no site files
      with_template_dir(tmp) do
        ContentTemplate::TYPES.each do |type|
          kit = ContentTemplate::KIT_DIR.join("#{type}_template.md").read
          assert_equal kit, ContentTemplate.template_content(type),
            "#{type}: expected the kit template when the site file is absent"
        end
      end
    end
  end

  test "frontmatter_for keeps every required field even from a template with no frontmatter" do
    Dir.mktmpdir do |tmp|
      with_template_dir(tmp) do
        ContentTemplate::TYPES.each do |type|
          File.write(File.join(tmp, "#{type}_template.md"), "Just a body, no frontmatter.\n")
          metadata, body = ContentTemplate.frontmatter_for(type)

          ContentTemplate.required_names(type).each do |name|
            assert metadata.key?(name),
              "#{type}: frontmatter_for dropped required key #{name.inspect}"
          end
          # The body is now scaffolded per type (ContentScaffold), so the
          # template's own body is composed in rather than being the whole thing.
          assert_includes body, "Just a body, no frontmatter.",
            "#{type}: scaffolding dropped the template's own body"
        end
      end
    end
  end

  test "frontmatter_for stamps a fresh date on posts and applies overrides" do
    metadata, = ContentTemplate.frontmatter_for("post", "title" => "Hello")

    assert_equal "Hello", metadata["title"]
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}\z/, metadata["date"].to_s,
      "post frontmatter should stamp a fresh ISO date at create time")
  end

  private

  # Point ContentTemplate at a throwaway site/system/templates dir for the block,
  # then restore the real one. (Minitest 6 ships no `stub`, so we swap by hand.)
  def with_template_dir(dir)
    original = ContentTemplate.method(:dir)
    ContentTemplate.define_singleton_method(:dir) { dir }
    yield
  ensure
    ContentTemplate.define_singleton_method(:dir, original)
  end
end
