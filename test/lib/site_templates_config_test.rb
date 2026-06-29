require "test_helper"
require "yaml"
require "erb"

# Guards the seeded config templates (lib/site_templates/) against drifting
# from the keys the app actually reads. KEYS ONLY — values are per-site and
# change like any real install.
#
# This covers the configs that have an AUTHORITATIVE definition in code, so
# the assertions can't themselves drift:
#   * podcast.yml → PodcastConfig::CANONICAL_FIELDS
#   * fonts.yml   → the `fonts:` wrapper + family/regular the config editor
#                   and AssetsHelper#font_face_css read.
#
# The broader, fuzzier "/site has keys the template lacks" sweep (for
# configs with no single canonical code list) is the advisory check in
# bin/sync-from-site — run before a release. Keep these two in mind as a
# pair: this test BLOCKS on the known-authoritative configs; the sync
# script SURFACES everything else for human review.
class SiteTemplatesConfigTest < ActiveSupport::TestCase
  TEMPLATES = Rails.root.join("lib", "site_templates")

  test "podcast.yml.erb seeds exactly the canonical podcast fields, in order" do
    rendered = render_erb(
      TEMPLATES.join("features/podcast/system/features/podcast.yml.erb"),
      author: "Author", author_email: "author@example.com", year: "2026",
      copyright_holder: "Author", site_url: "https://example.com"
    )
    data    = YAML.safe_load(rendered)
    podcast = data.values.first # single entry keyed by the podcast slug

    assert_equal PodcastConfig::CANONICAL_FIELDS, podcast.keys,
      "podcast.yml template keys drifted from PodcastConfig::CANONICAL_FIELDS — " \
      "add/remove/reorder fields in the template to match the model."
  end

  test "fonts.yml seeds the structure AssetsHelper + the config editor read" do
    data = YAML.safe_load(File.read(TEMPLATES.join("minimum/system/global/fonts.yml")))

    assert data.key?("fonts"),  "fonts.yml must wrap roles under a `fonts:` key"
    assert data.key?("themes"), "fonts.yml must have a `themes:` key"

    %w[heading body mono accent].each do |role|
      assert data["fonts"].key?(role), "fonts.yml missing font role: #{role}"
      assert data["fonts"][role].key?("family"),  "fonts.#{role} missing `family`"
      assert data["fonts"][role].key?("regular"), "fonts.#{role} missing `regular` (not `source`)"
    end
  end

  private

  # Render a .yml.erb template with the locals the loader supplies, so we
  # can inspect the keys it actually produces.
  def render_erb(path, **locals)
    b = binding
    locals.each { |k, v| b.local_variable_set(k, v) }
    ERB.new(File.read(path), trim_mode: "-").result(b)
  end
end
