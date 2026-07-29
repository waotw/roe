# frozen_string_literal: true

require "test_helper"

# ContentMetadataSchema is the field list the editor offers. Several other
# systems describe the same fields independently — Post::POST_TYPES, the
# Stimulus controller's coreFieldNames, ContentTemplate::REQUIRED, and
# Product::REQUIRED_FIELDS. Rather than collapse them (which would mean
# reshaping POST_TYPES and rewriting editor JS), these tests pin them to each
# other so drift fails a build instead of silently producing a dead field.
class ContentMetadataSchemaTest < ActiveSupport::TestCase
  def fields(type, metadata: {})
    ContentMetadataSchema.fields_for(type, metadata: metadata)
  end

  test "every field is well-formed for every type" do
    ContentMetadataSchema::TYPES.each do |type|
      fields(type).each do |name, config|
        assert name.present?, "#{type} has a blank field name"
        assert_includes %i[text textarea select datetime], config[:type],
          "#{type}.#{name} has a bad type: #{config[:type].inspect}"
        assert config[:label].present?, "#{type}.#{name} missing label"
        if config[:type] == :select
          assert config[:options].is_a?(Array), "#{type}.#{name} select needs an options array"
        end
      end
    end
  end

  test "unknown resource types fall back to the page fields" do
    assert_equal fields("page").keys, fields("documentation").keys
  end

  test "field order is stable — the controller writes YAML in this order" do
    assert_equal %w[title subtitle date post_type status], fields("post").keys.first(5)
    assert_equal "related", fields("post").keys.last
  end

  # The bug this module was extracted to prevent: `release` and `track_number`
  # were declared in Post::POST_TYPES but absent here, so the editor's auto-add
  # (which requires a known field) never surfaced them.
  test "every per-post-type field in Post::POST_TYPES is a known editor field" do
    known = fields("post").keys
    Post::POST_TYPES.each do |type, config|
      config[:metadata_fields].to_a.each do |field|
        assert_includes known, field[:name].to_s,
          "Post::POST_TYPES[:#{type}] declares `#{field[:name]}` but the editor doesn't know it"
      end
    end
  end

  test "per-type required flags come through from Post::POST_TYPES" do
    music = fields("post", metadata: { "post_type" => "music" })
    assert music["audio"][:required], "audio is required for music"

    article = fields("post", metadata: { "post_type" => "article" })
    assert_not article["audio"][:required], "audio is not required for an article"
  end

  test "the guid hint changes for imported posts" do
    plain    = fields("post")
    imported = fields("post", metadata: { "substack_post_id" => "123" })

    assert_match(/Auto-generated/, plain["guid"][:hint])
    assert_match(/Substack/, imported["guid"][:hint])
  end

  test "a non-hash metadata argument is tolerated" do
    assert fields("post", metadata: nil).key?("title")
    assert fields("post", metadata: "junk").key?("title")
  end

  # --- Cross-system drift guards -------------------------------------------

  # coreFieldNames is hand-maintained in the Stimulus controller (the fields
  # shown regardless of post_type). Deriving it would mean touching the editor
  # JS, so pin it instead.
  test "the controller's coreFieldNames all exist in the post schema" do
    js = File.read(Rails.root.join("app/javascript/controllers/metadata_editor_controller.js"))
    listed = js[/coreFieldNames\s*=\s*\[(.*?)\]/m, 1].to_s.scan(/"([^"]+)"/).flatten
    assert listed.any?, "could not parse coreFieldNames out of the controller"

    known = fields("post").keys
    listed.each do |name|
      assert_includes known, name, "coreFieldNames lists `#{name}`, which the schema doesn't define"
    end
  end

  # ContentTemplate::REQUIRED drives what new files get; it carries default
  # VALUES the schema doesn't, so it stays separate — but the two must at least
  # agree on which fields are required.
  test "ContentTemplate::REQUIRED fields are known and marked required" do
    ContentTemplate::TYPES.each do |type|
      schema = fields(type)
      ContentTemplate.required_names(type).each do |name|
        assert_includes schema.keys, name, "ContentTemplate requires `#{name}` for #{type}, unknown to the schema"
        assert schema[name][:required], "#{type}.#{name} is required at create but not marked required in the schema"
      end
    end
  end

  test "Product::REQUIRED_FIELDS are known and marked required" do
    schema = fields("product")
    Product::REQUIRED_FIELDS.each do |name|
      assert_includes schema.keys, name, "Product requires `#{name}`, unknown to the schema"
      assert schema[name][:required], "product.#{name} is required to publish but not marked required in the schema"
    end
  end

  # The collection builder offers a post_type filter; it drifted once already
  # (music shipped without being added).
  test "the collection builder offers every post type" do
    offered = CollectionBuilderSchema.fields.find { |f| f[:key] == "post_type" }[:options]
    Post::POST_TYPES.keys.each do |type|
      assert_includes offered, type.to_s, "collection builder can't filter by `#{type}`"
    end
  end
end
