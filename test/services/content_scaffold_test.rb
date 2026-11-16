# frozen_string_literal: true

require "test_helper"

# New content arrives with the markdown its type needs, so an author doesn't
# have to know the block syntax to get a working player or buy button. Blocks
# are live (they resolve from metadata at render), and any block whose value is
# missing is skipped rather than written empty.
class ContentScaffoldTest < ActiveSupport::TestCase
  # A store with a cart. The test site's store.yml comes and goes with other
  # tests, and no store.yml reads as Snipcart off — so say which this is.
  setup { SiteFeature.stubs(:snipcart_enabled?).returns(true) }

  def body(type, metadata = {}, template_body = "")
    ContentScaffold.body_for(type, metadata: metadata, template_body: template_body)
  end

  # --- posts: the title stays out of the body ------------------------------

  test "a post gets no title heading — the layout renders it from metadata" do
    result = body("post", { "title" => "My Post", "post_type" => "article" })

    assert_not_includes result, "# My Post",
      "the post layout draws the title; a body heading would double it"
  end

  test "an article scaffolds nothing but its template body" do
    assert_equal "Write here.", body("post", { "post_type" => "article" }, "Write here.").strip
  end

  # --- posts: the layout draws the player ------------------------------

  test "media posts get no player card — their layout draws the player" do
    %w[audio video podcast music].each do |type|
      result = body("post", { "post_type" => type, "podcast" => "myshow", "release" => "ep" }, "Notes.")
      assert_not_includes result, "type: player", "#{type}: the layout's player part supplies it"
      assert_includes result, "Notes."
    end
  end

  test "a podcast episode gets no episode list — the layout draws it" do
    assert_not_includes body("post", { "post_type" => "podcast", "podcast" => "myshow" }), "template: playlist"
  end

  test "a music track gets no track list — the layout draws it" do
    assert_not_includes body("post", { "post_type" => "music", "release" => "summer-ep" }), "template: playlist"
  end

  # --- pages: the title IS in the body ------------------------

  test "a page gets a title heading, because its view doesn't render one" do
    assert_includes body("page", { "title" => "About" }), "# About"
  end

  test "a product's body is only its writing — the layout draws title, image and button" do
    result = body("product", { "title" => "Zine", "price" => "12.00", "sku" => "Z1", "image" => "/media/images/zine.jpg" }, "About it.")

    assert_equal "About it.", result.strip
  end

  # --- the template body is composed in, not replaced ----------------------

  test "the editable template body lands in the content slot" do
    result = body("post", { "post_type" => "podcast", "podcast" => "s" }, "My boilerplate.")
    assert_includes result, "My boilerplate."
  end

  test "an unknown type just returns the template body" do
    assert_equal "Plain.", body("documentation", { "title" => "D" }, "Plain.").strip
  end

  # --- the scaffold lists themselves ---------------------------------------

  test "every post type declares a scaffold, and only of known blocks" do
    known = %i[content title playlist]
    Post::POST_TYPES.each do |type, config|
      assert config[:scaffold].present?, "#{type} has no scaffold"
      assert_includes config[:scaffold], :content, "#{type} must place the body somewhere"
      (config[:scaffold] - known).tap do |unknown|
        assert unknown.empty?, "#{type} scaffolds unknown block(s): #{unknown.inspect}"
      end
    end
  end
end
