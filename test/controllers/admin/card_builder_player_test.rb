# frozen_string_literal: true

require "test_helper"

# The player card's Audio and Video fields each get a Choose… button that
# opens the media picker for that kind (card_builder#pickMedia).
class Admin::CardBuilderPlayerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    # The edit action reads the file, so it has to exist on disk.
    meta = { "title" => "Player Builder", "url_name" => "player-builder", "status" => "draft", "post_type" => "audio" }
    @path = File.join(RoeSitePaths::SITE_PATH, "posts", "player-builder.md")
    FileUtils.mkdir_p(File.dirname(@path))
    File.write(@path, "#{meta.to_yaml}---\nBody.\n")
    @post = Post.create!(file_path: @path, content: "Body.", metadata: meta)
  end

  teardown { FileUtils.rm_f(@path) }

  test "the editor's Card menu has Player, and its media fields can open the picker" do
    get edit_admin_post_path(@post)

    assert_response :success
    assert_select "button[data-action='click->card-builder#open'][data-card-type='player']", text: "Player"
    group = css_select("[data-card-builder-target=group][data-cb-type=player]").first
    assert group, "the player group is in the builder"
    %w[audio video].each do |kind|
      assert group.at_css("input[data-cb-field=#{kind}]")
      assert group.at_css("button[data-cb-pick=#{kind}][data-cb-pick-field=#{kind}][data-action='click->card-builder#pickMedia']"),
        "#{kind} has a Choose… button for #{kind} files"
    end
    assert group.at_css("select[data-cb-field=show_duration]"), "show_duration is offered"
    assert_nil group.at_css("button[data-cb-pick-field=title]"), "only media fields get one"
  end
end
