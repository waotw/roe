# frozen_string_literal: true

require "test_helper"

# New content arrives with the markdown its type needs, so an author doesn't
# have to know the block syntax to get a working player or buy button. Blocks
# are live (they resolve from metadata at render), and any block whose value is
# missing is skipped rather than written empty.
class ContentScaffoldTest < ActiveSupport::TestCase
  def body(type, metadata = {}, template_body = "")
    ContentScaffold.body_for(type, metadata: metadata, template_body: template_body)
  end

  # --- posts: the title stays out of the body ------------------------------

  test "a post gets no title heading — the layout renders it from metadata" do
    result = body("post", { "title" => "My Post", "post_type" => "article" })

    assert_not_includes result, "# My Post",
      "posts/_header.html.erb already renders the title; a body heading would double it"
  end

  test "an article scaffolds nothing but its template body" do
    assert_equal "Write here.", body("post", { "post_type" => "article" }, "Write here.").strip
  end

  # --- posts: players ------------------------------------------------------

  test "audio and video posts get a player card" do
    %w[audio video].each do |type|
      result = body("post", { "post_type" => type })
      assert_includes result, "```card", "#{type} should scaffold a player"
      assert_includes result, "type: player"
    end
  end

  test "a podcast episode gets a player above the body and an episode list below" do
    result = body("post", { "post_type" => "podcast", "podcast" => "myshow" }, "Show notes.")

    assert_includes result, "type: player"
    assert_includes result, "template: playlist"
    assert_includes result, "podcast: myshow"
    assert_includes result, "order: episode_number"
    assert_operator result.index("type: player"), :<, result.index("Show notes.")
    assert_operator result.index("Show notes."), :<, result.index("template: playlist"),
      "the episode list belongs below the writing, as the ERB page had it"
  end

  test "a music track gets a player and its release's track list" do
    result = body("post", { "post_type" => "music", "release" => "summer-ep" })

    assert_includes result, "type: player"
    assert_includes result, "post_type: music"
    assert_includes result, "release: summer-ep"
    assert_includes result, "order: track_number"
  end

  test "the playlist is skipped until the association is known" do
    podcast = body("post", { "post_type" => "podcast" })
    music   = body("post", { "post_type" => "music" })

    assert_includes podcast, "type: player", "the player still works with no podcast set"
    assert_not_includes podcast, "template: playlist",
      "without a podcast key the collection would gather every episode on the site"
    assert_not_includes music, "template: playlist"
  end

  # --- pages and products: the title IS in the body ------------------------

  test "a page gets a title heading, because its view doesn't render one" do
    assert_includes body("page", { "title" => "About" }), "# About"
  end

  test "a product gets a title and a buy button that shows its price" do
    result = body("product", { "title" => "Zine", "price" => "12.00", "sku" => "Z1" })

    assert_includes result, "# Zine"
    assert_includes result, "```button"
    assert_includes result, "text: Add to Cart"
  end

  test "a product's image block is skipped until there's an image" do
    without = body("product", { "title" => "Zine" })
    with    = body("product", { "title" => "Zine", "image" => "/media/images/zine.jpg" })

    assert_not_includes without, "![", "an empty src would render a broken image"
    assert_includes with, "![Zine](/media/images/zine.jpg)"
  end

  test "no price is written into the body — the button renders it live" do
    result = body("product", { "title" => "Zine", "price" => "12.00" })

    assert_not_includes result, "12.00",
      "a frozen price would contradict metadata after an edit"
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
    known = %i[content title image player playlist buy_button]
    Post::POST_TYPES.each do |type, config|
      assert config[:scaffold].present?, "#{type} has no scaffold"
      assert_includes config[:scaffold], :content, "#{type} must place the body somewhere"
      (config[:scaffold] - known).tap do |unknown|
        assert unknown.empty?, "#{type} scaffolds unknown block(s): #{unknown.inspect}"
      end
    end
  end
end
