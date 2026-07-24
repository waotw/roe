require "test_helper"
require "tmpdir"

class FilesImporterRunnerTest < ActiveSupport::TestCase
  def build_tree(root)
    FileUtils.mkdir_p(File.join(root, "_posts"))
    FileUtils.mkdir_p(File.join(root, "pages"))
    FileUtils.mkdir_p(File.join(root, "images"))
    File.write(File.join(root, "images/pic.png"), "PNGDATA")
    File.write(File.join(root, "_posts/2024-01-05-hello.md"), <<~MD)
      ---
      title: Hello
      tags: [ruby]
      summary: A summary
      weird: keep me
      ---
      # Hello

      ![pic](../images/pic.png)
    MD
    File.write(File.join(root, "pages/about.md"), "---\ntitle: About\n---\nAbout us.\n")
    File.write(File.join(root, "index.html"),
               "<html><head><title>Home</title></head><body><main><p>Welcome</p></main></body></html>")
  end

  test "imports posts + pages, preserves filenames, copies media, and dedupes" do
    Dir.mktmpdir do |root|
      build_tree(root)
      Dir.mktmpdir do |posts|
        Dir.mktmpdir do |pages|
          Dir.mktmpdir do |media|
            runner = FilesImporter::Runner.new(
              root: root, posts_dir: posts, pages_dir: pages, media_root: media
            )
            r = runner.import

            assert_equal 1, r.posts, "the _posts file"
            assert_equal 2, r.pages, "pages/about.md + top-level index.html"

            assert File.exist?(File.join(posts, "2024-01-05-hello.md")), "filename preserved exactly"
            assert File.exist?(File.join(media, "images", "pic.png")), "bundled media copied"

            body = File.read(File.join(posts, "2024-01-05-hello.md"))
            assert_includes body, "](/media/images/pic.png)", "media link rewritten"
            assert_includes body, "tags:", "tags mapped"
            assert_includes body, "excerpt:", "summary → excerpt"
            assert_includes body, "weird:", "unmapped frontmatter passed through"
            assert_includes body, "source_file:", "dedup key stored"
            assert_equal [ "/media/images/pic.png" ], r.assets

            r2 = runner.import
            assert_equal 0, r2.posts
            assert_equal 0, r2.pages
            assert_equal 3, r2.skipped, "everything already imported"
          end
        end
      end
    end
  end

  test "overrides force a classification and can skip files" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, "ambiguous.md"), "just text with no signals")
      FileUtils.mkdir_p(File.join(root, "misc"))
      File.write(File.join(root, "misc/note.md"), "more text")

      Dir.mktmpdir do |posts|
        Dir.mktmpdir do |pages|
          Dir.mktmpdir do |media|
            runner = FilesImporter::Runner.new(
              root: root, posts_dir: posts, pages_dir: pages, media_root: media,
              overrides: { "ambiguous.md" => "page", "misc/note.md" => "skip" }
            )
            r = runner.import

            assert_equal 0, r.posts
            assert_equal 1, r.pages, "ambiguous.md forced to page"
            assert File.exist?(File.join(pages, "ambiguous.md"))
            assert_not File.exist?(File.join(posts, "note.md")), "note.md skipped"
          end
        end
      end
    end
  end
end
