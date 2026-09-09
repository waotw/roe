# frozen_string_literal: true

require "test_helper"

# The ACTION menu's labels and gates. "Form" said nothing about what it
# inserts, and Paywall — the item a writer reaches for most — was hidden until
# Stripe was connected, which is the wrong order for setting a site up.
class Admin::ActionMenuTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(User.take)
    # The edit action reads the file, so it has to exist on disk.
    meta = { "title" => "P", "url_name" => "p", "status" => "draft" }
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "p.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{meta.to_yaml}---\nBody.\n")
    @post = Post.create!(file_path: path, content: "Body.", metadata: meta)
  end

  def menu
    get edit_admin_post_path(@post)
    response.body
  end

  # Configured, but Stripe not connected — the state a site is in while it's
  # being built.
  test "Paywall is offered once payments are configured" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteFeature.stubs(:payments_feature_enabled?).returns(true)
    SiteFeature.stubs(:payments_enabled?).returns(false)

    get edit_admin_post_path(@post)

    assert_select "button[data-action-kind=?]", "paid_content", { count: 1 },
      "the item a writer reaches for most shouldn't wait on billing"
  end

  test "no Paywall when payments are off entirely" do
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteFeature.stubs(:payments_feature_enabled?).returns(false)
    SiteFeature.stubs(:payments_enabled?).returns(false)

    get edit_admin_post_path(@post)
    assert_select "button[data-action-kind=?]", "paid_content", count: 0
  end

  test "the form entry says what it's for" do
    SiteFeature.stubs(:members_enabled?).returns(true)

    body = menu

    assert_includes body, ">Member form</button>"
    assert_not_includes body, ">Form</button>"
  end

  # Members off means no member forms and no paywall — only Button remains.
  test "members off leaves the form entries out" do
    SiteFeature.stubs(:members_enabled?).returns(false)
    SiteFeature.stubs(:payments_feature_enabled?).returns(false)

    get edit_admin_post_path(@post)

    assert_select "button[data-action-block=?]", "form", count: 0
  end
end
