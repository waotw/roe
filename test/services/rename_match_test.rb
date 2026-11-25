require "test_helper"

class RenameMatchTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "posts"))
    FileUtils.mkdir_p(File.join(@dir, "pages"))
  end

  teardown { FileUtils.rm_rf(@dir) }

  def file(path, title, body)
    full = File.join(@dir, path)
    File.write(full, "---\ntitle: \"#{title}\"\nstatus: published\n---\n#{body}\n")
    full
  end

  def record(title, body)
    Post.new(content: "#{body}\n", metadata: { "title" => title })
  end

  test "the same title and text in the same folder is a rename" do
    new_file = file("posts/hello.md", "Welcome", "First words.")
    renames, unsure = RenameMatch.pairs({ "#{@dir}/posts/welcome.md" => record("Welcome", "First words.") }, [ new_file ])

    assert_equal({ "#{@dir}/posts/welcome.md" => new_file }, renames)
    assert_empty unsure
  end

  test "changed text, a changed title, or another folder is not" do
    old = "#{@dir}/posts/welcome.md"
    rec = record("Welcome", "First words.")

    [ file("posts/a.md", "Welcome", "First words, edited."),
      file("posts/b.md", "Hello", "First words."),
      file("pages/welcome.md", "Welcome", "First words.") ].each do |candidate|
      assert_empty RenameMatch.pairs({ old => rec }, [ candidate ]).first, File.basename(candidate)
    end
  end

  test "a similar name alone is not a rename" do
    renames, = RenameMatch.pairs({ "#{@dir}/posts/music.md" => record("Music", "One.") },
                                 [ file("posts/music-2.md", "Music 2", "Two.") ])
    assert_empty renames
  end

  test "two matching files, or two old files matching one, are left alone" do
    rec = record("Episode", "{{ player }}")
    one = file("posts/one.md", "Episode", "{{ player }}")
    two = file("posts/two.md", "Episode", "{{ player }}")

    renames, unsure = RenameMatch.pairs({ "#{@dir}/posts/old.md" => rec }, [ one, two ])
    assert_empty renames
    assert_equal [ "#{@dir}/posts/old.md" ], unsure

    renames, unsure = RenameMatch.pairs({ "#{@dir}/posts/a.md" => rec, "#{@dir}/posts/b.md" => rec }, [ one ])
    assert_empty renames
    assert_equal 2, unsure.size
  end

  test "an empty body is never matched" do
    assert_empty RenameMatch.pairs({ "#{@dir}/posts/x.md" => record("X", "") }, [ file("posts/y.md", "X", "") ]).first
  end
end
