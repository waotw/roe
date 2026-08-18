# frozen_string_literal: true

require "test_helper"

# The editor's markdown checks. Content comes in the request body because the
# editor lints the textarea, which hasn't been saved — reading from disk would
# check the wrong thing.
class Admin::MarkdownControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  def json = JSON.parse(response.body)

  test "check reports issues with lines, labels and fixability" do
    post admin_check_markdown_path, params: { content: "Intro\n- an item\n" }

    assert_response :success
    issue = json["issues"].first
    assert_equal "list_spacing", issue["type"]
    assert_equal 2, issue["line"]
    assert issue["fixable"]
    assert issue["label"].present?, "the human label comes from ISSUE_TYPES"
    assert_equal 1, json["fixable_count"]
  end

  test "check on clean content returns nothing to do" do
    post admin_check_markdown_path, params: { content: "# Title\n\nA paragraph.\n" }

    assert_response :success
    assert_empty json["issues"]
    assert_equal 0, json["fixable_count"]
  end

  test "an unclosed fence is reported but not fixable" do
    post admin_check_markdown_path, params: { content: "```ruby\nputs 1\n" }

    assert_response :success
    assert_equal 0, json["fixable_count"], "guessing where a fence closes could eat the document"
    assert_not json["issues"].first["fixable"]
  end

  test "fix returns corrected content, what it changed, and what it didn't" do
    post admin_fix_markdown_path, params: { content: "Intro\n- an item\n" }

    assert_response :success
    assert_equal "Intro\n\n- an item\n", json["content"]
    assert_equal 1, json["applied"].size
    assert_empty json["remaining"]
  end

  test "fix leaves unfixable content byte-identical" do
    content = "```ruby\nputs 1\n"
    post admin_fix_markdown_path, params: { content: content }

    assert_response :success
    assert_equal content, json["content"]
    assert_empty json["applied"]
    assert_equal 1, json["remaining"].size, "still reported, just not changed"
  end

  test "empty content is handled rather than erroring" do
    post admin_check_markdown_path, params: { content: "" }

    assert_response :success
    assert_empty json["issues"]
  end

  test "the endpoints require an admin session" do
    delete session_path

    post admin_check_markdown_path, params: { content: "x" }
    assert_response :redirect
  end

  # The panel lives in shared/_editor, so every resource that renders the editor
  # gets it — posts, pages, products and emails — rather than four copies.
  test "the warnings panel renders in the editor, above the writing area" do
    path = File.join(RoeSitePaths::SITE_PATH, "posts", "doctor-panel.md")
    File.write(path, "---\ntitle: \"Doctor Panel\"\nstatus: draft\nurl_name: doctor-panel\n---\nBody.\n")
    record = Post.create!(file_path: path, content: "Body.",
      metadata: { "title" => "Doctor Panel", "status" => "draft", "url_name" => "doctor-panel" })

    get edit_admin_post_path(record)

    assert_response :success
    # Mounted alongside the editor controller, because the trigger button and
    # the results panel are sibling subtrees — anything narrower can't see both.
    assert_match(/data-controller="editor[^"]*markdown-doctor"/, response.body)
    assert_includes response.body, admin_check_markdown_path

    # Typing is detected by listening for bubbled `input` on the controller
    # element, so it has to be an ancestor of the textarea. It also must not be
    # the editor form: the first form inside it is the duplicate button's, which
    # the textarea isn't in — binding there meant no check ever ran while typing
    # and issues only refreshed on save.
    controller_el = Nokogiri::HTML(response.body).at_css('[data-controller~="markdown-doctor"]')
    assert controller_el.at_css("#content-textarea"),
      "the textarea must sit inside the controller element for input to bubble to it"
    assert_not_equal "form", controller_el.name

    # Two sections: what Roe can rewrite, and what only the writer can decide.
    assert_includes response.body, 'data-markdown-doctor-target="fixableSection"'
    assert_includes response.body, 'data-markdown-doctor-target="manualSection"'
    assert_includes response.body, 'data-markdown-doctor-target="fixButton"'

    # No Check button anywhere: checking is automatic, so the only trigger left
    # in the markup is the tab, which opens results that are already there.
    assert_not_includes response.body, "Check Markdown"
    assert_not_includes response.body, "markdown-doctor#check"

    # Status indicator, grey until the first check answers — a document with
    # problems must never flash green on the way in.
    assert_match(/data-markdown-doctor-target="dot"[^>]*bg-gray-300/, response.body)
    assert_operator response.body.index('data-markdown-doctor-target="panel"'), :<,
      response.body.index('id="content-textarea"'),
      "results panel belongs above the writing area, with the TOC"

    # Tabs: the two toggles share one row and the space below it, so each click
    # closes the other panel. Both directions, or they end up stacked and the
    # writing area gets pushed off screen.
    assert_includes response.body,
      "click->editor#toggleTOC click->markdown-doctor#closePanel"
    assert_includes response.body,
      "click->markdown-doctor#togglePanel click->editor#closeTOC"
    assert_equal 1, response.body.scan("click->editor#toggleTOC").size,
      "one table-of-contents toggle — the old standalone row should be gone"

    # Fix All and Undo Fix change the content in one click, with no typing pause
    # for the preview's debounce to wait at the end of, so they tell the editor
    # to push the open preview tab straight away.
    assert_includes response.body,
      "markdown-doctor:contentChanged-&gt;editor#refreshPreview"

    # The active-tab look is CSS keyed on the panel's own visibility (:has), so
    # these class names are the join between markup and application.css — rename
    # one side only and the tab silently stops highlighting.
    assert_includes response.body, "editor-tab editor-tab-toc"
    assert_includes response.body, "editor-tab editor-tab-markdown"
    assert_includes response.body, "editor-panel-toc"
    assert_includes response.body, "editor-panel-markdown"

    # Scrolling collapses the toolbar's lower half, which would swallow results
    # the writer just asked for. The TOC is deliberately NOT pinned.
    assert_match(/data-markdown-doctor-target="panel"\s+data-sticky-toolbar-keep-open/,
      response.body)
    assert_includes response.body, "markdown-doctor:opened->sticky-toolbar#reveal"
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end
