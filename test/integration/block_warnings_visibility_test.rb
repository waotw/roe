# frozen_string_literal: true

require "test_helper"

# Roe explains a block it couldn't render with an amber warning box. Those used
# to be development-only, which meant anyone running Roe on a server saw nothing
# at all when a block quietly rendered empty.
#
# They now show in the editor preview in any environment, and nowhere else.
#
# This runs in the test environment, where warnings are off, so a bare
# assert_not passes whether or not suppression works. Assertions here are
# therefore either about the preview flag (which turns warnings on in any
# environment) or made under a stubbed development environment (where something
# has to actively turn them off).
class BlockWarningsVisibilityTest < ActionDispatch::IntegrationTest
  # An unknown collection source: the block renders nothing, with no clue why.
  BROKEN = "```collection\nsource: blogs\n```\n"

  setup do
    @path = File.join(RoeSitePaths::SITE_PATH, "posts", "broken-block.md")
    File.write(@path, "---\ntitle: \"Broken Block\"\nstatus: published\nurl_name: broken-block\n---\n#{BROKEN}")
    @post = Post.create!(
      file_path: @path, content: BROKEN,
      metadata: { "title" => "Broken Block", "status" => "published", "url_name" => "broken-block" },
    )
  end

  teardown { File.delete(@path) if File.exist?(@path) }

  def warning?(body) = body.include?("⚠️")

  def in_development
    Rails.env.stubs(:development?).returns(true)
    yield
  ensure
    Rails.env.unstub(:development?)
  end

  test "a published page never shows a block warning" do
    get "/posts/broken-block"

    assert_response :success
    assert_not warning?(response.body),
      "a reader must never be handed an editor diagnostic"
  end

  test "a published page shows no warning even to a signed-in admin" do
    sign_in_as(User.take)
    get "/posts/broken-block"

    assert_response :success
    assert_not warning?(response.body),
      "the published URL is the published URL, whoever is looking at it"
  end

  test "the editor preview explains the block" do
    sign_in_as(User.take)
    get preview_admin_post_path(@post)

    assert_response :success
    assert warning?(response.body), "the preview is where the writer finds out"
    assert_includes response.body, "Unknown collection source"
  end

  test "previewing unsaved content explains the block too" do
    sign_in_as(User.take)
    post preview_admin_post_path(@post),
      params: { content: BROKEN, metadata: "title: \"Broken Block\"\nurl_name: broken-block\n" }

    assert_response :success
    assert warning?(response.body)
  end

  # A draft is only ever reachable through the preview, which is exactly where
  # the warning belongs.
  test "a draft previews with its warning" do
    @post.update!(metadata: @post.metadata.merge("status" => "draft"))
    sign_in_as(User.take)

    get preview_admin_post_path(@post)

    assert_response :success
    assert warning?(response.body)
  end

  # The whole point of the feature: someone writing on their own machine finds
  # out the block is broken without opening the preview.
  test "a published page does show the warning in development" do
    in_development { get "/posts/broken-block" }

    assert_response :success
    assert warning?(response.body),
      "a local author browsing their own site is the case this was built for"
  end

  # Static output outlives the request that made it, so it's excluded outright
  # rather than by trusting the preview flag to be false.
  test "a static render is silent whatever it is asked for" do
    in_development do
      assert_not warning?(@post.to_html(static: true)),
        "a generated file must not carry a warning into the world"
      assert_not warning?(@post.to_html(preview: true, static: true)),
        "not even when the render that produced it was a preview"

      assert warning?(@post.to_html),
        "precondition — without static, this same render warns"
    end
  end
end
