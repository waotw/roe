require "test_helper"

# The config templates Roe ships have to already be in the form Roe writes.
#
# They weren't. A template written by hand used "" where Psych emits '', and an
# unquoted 2026-06-01 parsed as a Date where the admin form posts a String. So
# the first time anyone saved a settings page, the file was rewritten into
# canonical form — a real content change, which Site Sync correctly reported as
# drift the user hadn't caused. Saving again was a no-op, which made it look
# like a phantom.
#
# Fixed by shipping the templates canonical. This keeps them that way: edit one
# by hand and this fails with the exact diff.
class CanonicalTemplatesTest < ActiveSupport::TestCase
  ROOT = Rails.root.join("lib", "site_templates")

  # store/members/podcast interpolate ERB into values (and store injects raw
  # YAML), so their canonical form is only knowable after rendering. music has
  # no ERB tags, so it round-trips like plain YAML.
  TEMPLATES = (Dir.glob(ROOT.join("**", "*.yml")).reject { |f| f.include?("_versions.yml") } +
               [ ROOT.join("features", "music", "system", "features", "music.yml.erb").to_s ]).sort.freeze

  def canonical(raw)
    stringify(YAML.load(raw, permitted_classes: [ Date, Time ]) || {})
      .to_yaml.sub(/\A---\s*\n/, "")
  end

  # The admin form posts every value as a string, so a template holding a real
  # Date would be rewritten on first save. Match what the form produces.
  def stringify(object)
    case object
    when Hash               then object.transform_values { |v| stringify(v) }
    when Array              then object.map { |v| stringify(v) }
    when Date, Time, DateTime then object.strftime("%Y-%m-%d")
    else object
    end
  end

  test "there are templates to check" do
    assert_operator TEMPLATES.size, :>=, 10, "precondition — the glob found the templates"
  end

  TEMPLATES.each do |path|
    relative = Pathname.new(path).relative_path_from(Rails.root).to_s

    test "#{relative} ships in the form Roe writes" do
      raw = File.read(path)

      assert_equal canonical(raw), raw,
        "#{relative} isn't canonical — installing it and saving once would rewrite " \
        "the file and show up as Site Sync drift the user didn't cause."
    end
  end

  # The blank line and the Date that started this.
  test "no template carries a value that parses as a Date" do
    TEMPLATES.each do |path|
      loaded = YAML.load(File.read(path), permitted_classes: [ Date, Time ]) || {}
      dates  = []
      walk = ->(o, trail) do
        case o
        when Hash  then o.each { |k, v| walk.call(v, trail + [ k ]) }
        when Array then o.each_with_index { |v, i| walk.call(v, trail + [ i ]) }
        when Date, Time, DateTime then dates << trail.join(".")
        end
      end
      walk.call(loaded, [])

      assert_empty dates,
        "#{File.basename(path)} has date-typed values at #{dates.join(', ')} — the form " \
        "posts strings, so these would be rewritten on first save."
    end
  end
end
