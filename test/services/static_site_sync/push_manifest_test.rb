require "test_helper"
require "tmpdir"
require "json"
require "digest"

class StaticSiteSync::PushManifestTest < ActiveSupport::TestCase
  def with_site
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      yield root, StaticSiteSync::PushManifest.new(root: root)
    end
  end

  def write_file(root, rel, content)
    path = root.join(rel)
    path.dirname.mkpath
    path.write(content)
  end

  def write_manifest(root, files)
    root.join(".push_manifest.json").write(JSON.pretty_generate("files" => files))
  end

  test "full_diff uploads every current file and prunes recorded-but-missing ones" do
    with_site do |root, manifest|
      write_file(root, "a.html", "A")
      write_file(root, "sub/b.html", "B")
      # Manifest records a stale hash for a.html plus a file that's since gone.
      write_manifest(root, "a.html" => { "sha256" => "stale" }, "gone.html" => { "sha256" => "x" })

      full = manifest.full_diff
      assert_equal ["a.html", "sub/b.html"], full.upload_paths.sort
      assert_equal ["gone.html"], full.deleted
    end
  end

  test "full_diff re-uploads a file even when the incremental diff thinks it's in sync" do
    with_site do |root, manifest|
      write_file(root, "a.html", "A")
      # Manifest already records the current hash — so the incremental diff is empty
      # (this is the drift trap: manifest says synced even if the host lost the file).
      write_manifest(root, "a.html" => { "sha256" => Digest::SHA256.hexdigest("A") })

      assert manifest.diff.empty?, "unchanged file should be absent from the incremental diff"
      assert_equal ["a.html"], manifest.full_diff.upload_paths
    end
  end
end
