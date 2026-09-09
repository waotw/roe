# frozen_string_literal: true

require "test_helper"

# Documentation is scoped by a `file_path LIKE` prefix, so that prefix has to
# match what ContentSync stored. On Fly, /rails/site is a symlink to /data/site
# and stored paths are the resolved ones — but RoeSitePaths.normalize falls back
# to the un-resolved path when realpath can't find the directory.
#
# Caching that fallback is unrecoverable: every query then looks under
# /rails/site while the records say /data/site, matching nothing, for the life
# of the process. The collection renders empty and the tag check reports that no
# tags exist — which is what go-roe.com was doing after an update.
class DocumentationPathTest < ActiveSupport::TestCase
  def reset_memo
    Documentation.remove_instance_variable(:@normalized_documentation_path)
  rescue NameError
    nil
  end

  setup { reset_memo }
  teardown { reset_memo }

  test "the resolved path is remembered once the directory is there" do
    assert Dir.exist?(RoeSitePaths::SITE_DOCUMENTATION_PATH), "fixture site should have docs"

    first = Documentation.normalized_documentation_path

    assert_equal first, Documentation.instance_variable_get(:@normalized_documentation_path)
    assert_equal first, Documentation.normalized_documentation_path
  end

  # The important half. A missing directory still answers, so callers work —
  # it just isn't allowed to become the answer forever.
  test "a missing directory is answered but never cached" do
    RoeSitePaths.stubs(:normalize).returns("/rails/site/documentation")
    Dir.stubs(:exist?).with(RoeSitePaths::SITE_DOCUMENTATION_PATH).returns(false)

    assert_equal "/rails/site/documentation", Documentation.normalized_documentation_path
    assert_nil Documentation.instance_variable_get(:@normalized_documentation_path),
      "a guess must not outlive the moment it was guessed in"
  end

  test "it recovers once the directory appears" do
    RoeSitePaths.stubs(:normalize).returns("/rails/site/documentation")
    Dir.stubs(:exist?).with(RoeSitePaths::SITE_DOCUMENTATION_PATH).returns(false)
    Documentation.normalized_documentation_path

    RoeSitePaths.stubs(:normalize).returns("/data/site/documentation")
    Dir.stubs(:exist?).with(RoeSitePaths::SITE_DOCUMENTATION_PATH).returns(true)

    assert_equal "/data/site/documentation", Documentation.normalized_documentation_path,
      "the next call after the volume is there should get the real path"
  end

  # The symptom the memoisation bug produced: in_directory matches nothing and
  # all_tags reports no tags, so a `related:` collection renders empty and the
  # editor warns that every tag is unknown. Build the record against the same
  # normalized prefix ContentSync stores, rather than relying on whatever the
  # test site happens to have synced — with no docs on disk this passed or
  # failed by accident.
  test "docs in a subdirectory are found, and their tags with them" do
    path = File.join(Documentation.normalized_documentation_path, "roe", "getting-started.md")
    Documentation.create!(
      file_path: path,
      content: "# Getting Started",
      metadata: { "title" => "Getting Started", "url_name" => "getting-started",
                  "tags" => "getting-started, tutorial", "status" => "published" }
    )

    assert_equal 1, Documentation.in_directory("roe").count
    assert_includes Documentation.all_tags("roe"), "getting-started"
    assert_empty Documentation.in_directory("nope"), "the prefix actually scopes"
  end
end
