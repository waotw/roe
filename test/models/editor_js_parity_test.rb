require "test_helper"

# The metadata editor renders rows twice: server-side in
# _metadata_editor.html.erb, and client-side in metadata_editor_controller.js
# when a field is added from the menu. They have to agree, and they've drifted
# three times — most recently when three fields became checkboxes and the JS
# had no checkbox case, so adding one produced an empty row.
#
# Executing the JS here isn't possible, so this pins the contract that keeps
# breaking: every field type the schema can produce must have a branch in
# buildInputHtml. Cheap, and it catches the exact failure that shipped.
class EditorJsParityTest < ActiveSupport::TestCase
  CONTROLLER = Rails.root.join("app/javascript/controllers/metadata_editor_controller.js")

  def js = @js ||= File.read(CONTROLLER)

  # `case "text":` … in buildInputHtml.
  def handled_types
    # Anchored to the definition — `this.buildInputHtml(...)` is called earlier
    # in the file, and matching that grabs a chunk with no cases in it.
    body = js[/^  buildInputHtml\(.*?\n  \}/m].to_s
    assert body.present?, "couldn't find buildInputHtml in the controller"
    body.scan(/case\s+"([a-z]+)":/).flatten.uniq
  end

  def schema_types
    %w[post page product documentation].flat_map { |type|
      ContentMetadataSchema.fields_for(type).values.map { |c| (c[:type] || :text).to_s }
    }.uniq
  end

  test "every field type the schema uses has a branch in buildInputHtml" do
    missing = schema_types - handled_types

    assert_empty missing,
      "buildInputHtml has no case for #{missing.join(', ')} — a field of that type " \
      "added from the Add Field menu renders as nothing (default: return \"\")."
  end

  test "the parser actually found the cases" do
    assert_includes handled_types, "text", "precondition — parsing buildInputHtml works"
    assert_operator handled_types.size, :>=, 4
  end

  # The row wrapper is what makes a note line up with its field. Both builders
  # have to produce it, or a field added from the menu loses its note.
  test "the JS builds the same column wrapper as the ERB" do
    erb = File.read(Rails.root.join("app/views/shared/_metadata_editor.html.erb"))

    assert_match 'class="flex-1 min-w-0"', erb, "the ERB should wrap the field in a column"
    assert_match 'class="flex-1 min-w-0"', js, "the JS row builder should match it"
  end

  # A checkbox is a small square: it centres against its label, and the label
  # drops the top padding that lines text up. The ERB branches on this; the JS
  # hardcoded items-start and pt-1.5, so a checkbox added from the menu sat
  # slightly off until a save re-rendered it server-side.
  test "both JS row builders align a checkbox row the way the ERB does" do
    %w[_addKnownFieldByName addKnownFieldToForm].each do |builder|
      body = js[/^  #{builder}\(.*?\n  \}/m].to_s
      assert body.present?, "couldn't find #{builder}"

      assert_match(/isCheckbox \? "items-center" : "items-start"/, body,
        "#{builder} hardcodes row alignment — a checkbox row needs items-center")
      # Quote-agnostic: the label uses single quotes inside the interpolation so
      # the class attribute has no inner `"` — the styling test's capture regex
      # stops at the first one.
      assert_match(/isCheckbox \? ['"]{2} : ['"]pt-1\.5['"]/, body,
        "#{builder} hardcodes the label's pt-1.5, which misaligns a checkbox")
    end
  end

  # Both builders wrap the field in a column, or a menu-added field loses its
  # note and its alignment.
  test "both JS row builders emit the column wrapper" do
    %w[_addKnownFieldByName addKnownFieldToForm].each do |builder|
      body = js[/^  #{builder}\(.*?\n  \}/m].to_s

      assert_match 'class="flex-1 min-w-0"', body, "#{builder} builds a flat row"
      assert_match(/config\.note/, body, "#{builder} drops the field's note")
    end
  end

  # A note only renders if the builder knows about it.
  test "the JS renders a field's note" do
    assert_match(/config\.note/, js,
      "buildInputHtml's caller must render config.note, or menu-added fields lose it")
  end
end
