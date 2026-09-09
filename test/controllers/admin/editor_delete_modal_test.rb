# frozen_string_literal: true

require "test_helper"

# Deleting from an editor asked for a one-line browser confirm while deleting
# the identical file from the index asked you to type DELETE — the weaker guard
# on the screen where you've just been working on the thing. Both go through
# the modal now.
class Admin::EditorDeleteModalTest < ActionDispatch::IntegrationTest
  setup { @written = []; sign_in_as(User.take) }
  teardown { @written.each { |f| File.delete(f) if File.exist?(f) } }

  # The editor reads the file off disk, so the row alone isn't enough.
  def make(model, dir, n)
    path = File.join(RoeSitePaths::SITE_PATH, dir, "dm#{n}.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"DM#{n}\"\nstatus: \"published\"\n---\n\nBody.\n")
    @written << path

    # Product stores a path relative to /site; Post and Page store an absolute
    # one. Pre-existing in the models, not something this test can normalize.
    stored = model == Product ? "#{dir}/dm#{n}.md" : path

    model.create!(
      file_path: stored,
      content: "Body.",
      metadata: { "title" => "DM#{n}", "url_name" => "dm#{n}", "status" => "published" }
        .merge(model == Product ? { "price" => "10.00" } : {})
    )
  end

  def each_editor
    [ [ Post, "posts", "post", ->(r) { edit_admin_post_path(r) } ],
      [ Page, "pages", "page", ->(r) { edit_admin_page_path(r) } ],
      [ Product, "products", "product", ->(r) { edit_admin_product_path(r) } ] ].each_with_index do |(model, dir, type, path), i|
      yield model, type, path.call(make(model, dir, i))
    end
  end

  test "every editor's Delete opens the modal rather than a browser confirm" do
    each_editor do |_model, type, url|
      get url

      assert_response :success, "#{type} editor didn't render"
      assert_match 'data-action="delete"', response.body, "#{type} editor has no modal trigger"
      assert_match %(data-resource-type="#{type}"), response.body
      assert_no_match(/turbo_confirm|turbo-confirm/, response.body[/Delete.{0,400}/m].to_s,
        "#{type} editor still uses the browser confirm")
    end
  end

  # The trigger looks the modal up by id, so the markup has to be on the page.
  # products/edit never rendered it, which would have opened nothing at all.
  test "every editor renders the modal the trigger opens" do
    each_editor do |_model, type, url|
      get url

      assert_match %(id="delete-modal-#{type}"), response.body, "#{type} editor is missing the modal"
      assert_match %(id="delete-confirmation-input-#{type}"), response.body
      assert_match %(id="delete-item-title-#{type}"), response.body
    end
  end

  # Two modals sharing an id would break getElementById, and the partial is now
  # rendered by _editor_actions rather than by each view.
  test "the modal is rendered exactly once per editor" do
    each_editor do |_model, type, url|
      get url

      assert_equal 1, response.body.scan(%(id="delete-modal-#{type}")).size,
        "#{type} editor renders the modal more than once"
    end
  end

  # A single-resource page keeps the form action the modal was rendered with;
  # only index tables retarget it per row.
  test "the editor trigger omits data-delete-url" do
    each_editor do |_model, type, url|
      get url
      trigger = response.body[/<button[^>]*data-action="delete"[^>]*>/m]

      assert trigger.present?, "#{type} editor has no delete trigger"
      assert_no_match(/data-delete-url/, trigger,
        "#{type} would retarget the form instead of using its own action")
    end
  end

  test "the index tables still trigger the modal" do
    make(Post, "posts", 99)
    get admin_posts_path

    assert_match 'data-action="delete"', response.body
    assert_match "data-delete-url", response.body, "index rows retarget the shared form"
  end
end
