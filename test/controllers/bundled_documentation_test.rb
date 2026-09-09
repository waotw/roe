# frozen_string_literal: true

require "test_helper"

# Roe installs its documentation into site/documentation/roe/ so it travels
# with the site and can be edited. But those are the user's files — they can be
# deleted, renamed, or never installed, and then every admin link into them
# 404s. Those links appear exactly when something has gone wrong, which is the
# worst moment to hit a dead end.
#
# The same files already ship at lib/site_templates/minimum/documentation/roe/,
# so this is a fallback rather than a second copy to keep in step.
class BundledDocumentationTest < ActionDispatch::IntegrationTest
  SLUG = "troubleshoot-deployment"

  def bundled_dir = BundledDocumentation::ROOT.join("roe")

  setup { skip "no bundled docs in this checkout" unless bundled_dir.directory? }

  # The admin's help links are the reason this exists, and they have to work at
  # every setting — including the default, where Roe's docs aren't part of the
  # public site at all.
  test "an admin gets the app's copy even when the docs aren't published" do
    Documentation.stubs(:roe_docs_published?).returns(false)
    sign_in_as(User.take)

    get "/documentation/roe/#{SLUG}"

    assert_response :success
    assert_match "Troubleshooting", response.body
  end

  # A site set to "local" has decided these pages aren't part of it. The
  # fallback mustn't quietly put them back at a public URL.
  test "a visitor gets nothing when the docs aren't published" do
    Documentation.stubs(:roe_docs_published?).returns(false)

    get "/documentation/roe/#{SLUG}"

    assert_response :not_found
  end

  test "a visitor gets the app's copy once the docs are published" do
    Documentation.stubs(:roe_docs_published?).returns(true)

    get "/documentation/roe/#{SLUG}"

    assert_response :success
    assert_match "Troubleshooting", response.body
  end

  # Otherwise editing your own docs would appear to do nothing.
  test "the installed copy wins when both exist" do
    path = File.join(RoeSitePaths::SITE_PATH, "documentation", "roe", "bd-test.md")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "---\ntitle: \"Mine\"\nurl_name: \"#{SLUG}\"\nstatus: \"published\"\n---\n\nMy own words.")
    Documentation.create_or_update_from_file(path)

    get "/documentation/roe/#{SLUG}"

    assert_response :success
    assert_match "My own words", response.body
  ensure
    File.delete(path) if path && File.exist?(path)
    Documentation.remove_by_file_path(path) if path
  end

  test "the page says when it came from the app" do
    Documentation.stubs(:roe_docs_published?).returns(true)
    get "/documentation/roe/#{SLUG}"

    assert_match(/Roe's own copy of this page/, response.body)
  end

  test "a doc in neither place is still a 404" do
    Documentation.stubs(:roe_docs_published?).returns(true)
    get "/documentation/roe/no-such-page-anywhere"

    assert_response :not_found
  end

  # ── The scope comes off the URL ──────────────────────────────────────────

  test "a scope can't walk out of the bundled directory" do
    [ "../../..", "..", "roe/../../config", "roe%2F.." ].each do |scope|
      assert_nil BundledDocumentation.find(scope, SLUG), "#{scope.inspect} was accepted"
    end
  end

  test "an unknown scope finds nothing rather than erroring" do
    assert_nil BundledDocumentation.find("notes", SLUG)
    assert_not BundledDocumentation.available?("notes")
  end

  # ── The case this actually fixes ─────────────────────────────────────────
  #
  # `search.roe_docs` reads as a search setting, but ContentSync uses it to
  # decide whether to sync documentation/roe into the database at all — and it
  # purges what's already there when turned off. The files stay on disk; the
  # records don't. So every /documentation/roe/… URL 404'd, including the help
  # links in the admin, and nothing about the setting suggested it would.
  test "docs stay readable when they're excluded from the index" do
    assert_equal "local", Documentation.roe_docs_mode, "precondition — the default"
    assert_equal 0, Documentation.in_directory("roe").count
    sign_in_as(User.take)

    get "/documentation/roe/#{SLUG}"

    assert_response :success, "an admin help link would be dead here"
  end

  # ── The object it builds ─────────────────────────────────────────────────

  # Unsaved on purpose: it isn't the user's content and mustn't turn up in
  # their documentation lists, search or exports.
  test "the fallback doc is never persisted" do
    assert_no_difference -> { Documentation.count } do
      doc = BundledDocumentation.find("roe", SLUG)

      assert doc.new_record?
      assert doc.to_html.present?
    end
  end
end
