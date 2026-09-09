# frozen_string_literal: true

require "test_helper"

# Every published page on a members site carried a ⚠ and "missing required
# field: audience" — for pages that were public and working. site_controller
# gates only on `audience == "paid"`, so a blank audience already meant public.
class PageAudienceOptionalTest < ActiveSupport::TestCase
  setup do
    SiteFeature.stubs(:memberships_enabled?).returns(true)
    @path = File.join(RoeSitePaths::SITE_PATH, "pages", "zz-audience.md")
    File.write(@path, "---\ntitle: \"ZZ Audience\"\nurl_name: zz-audience\nstatus: published\n---\nBody.\n")
    @page = Page.create_or_update_from_file(@path)
  end

  teardown do
    FileUtils.rm_f(@path)
    Page.where(file_path: @path).destroy_all
  end

  test "a public page with no audience isn't flagged" do
    assert_empty @page.missing_site_gated_fields
    assert_not @page.needs_attention?, "a working public page was marked as needing attention"
  end

  test "audience is offered, not demanded, and defaults to public" do
    field = ContentMetadataSchema.fields_for("page")["audience"]

    assert_not field[:required], "a red asterisk on a choice almost nobody needs to make"
    assert_equal "everyone", field[:default]
  end

  # Different rule on purpose: getting free-vs-paid wrong on a post is
  # expensive in both directions, so the decision is forced.
  test "posts still require it when memberships are on" do
    assert ContentMetadataSchema.fields_for("post")["audience"][:required]
  end

  # The list was hand-maintained and fell behind when music was added.
  test "the collection filter offers every post type the site has" do
    options = CollectionBuilderSchema::FIELDS.find { |f| f[:key] == "post_type" }[:options]

    Post::POST_TYPES.keys.each do |type|
      assert_includes options, type.to_s, "collection builder can't filter by `#{type}`"
    end
  end
end
