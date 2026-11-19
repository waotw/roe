require "test_helper"

class FrontMatterTagsTest < ActiveSupport::TestCase
  def doc(front, body = "Body\n")
    "---\n#{front}---\n#{body}"
  end

  test "reads an inline list, a block list and a comma string" do
    assert_equal %w[a b], FrontMatterTags.read(doc("tags: [\"a\", \"b\"]\n"))
    assert_equal %w[a b], FrontMatterTags.read(doc("tags:\n  - a\n  - b\n"))
    assert_equal %w[a b], FrontMatterTags.read(doc("tags: a, b\n"))
    assert_equal [], FrontMatterTags.read(doc("title: x\n"))
    assert_nil FrontMatterTags.read("no front matter")
  end

  test "replaces only the tags line" do
    text = doc("title: Hello\ntags: [\"a\", \"b\"]\nstatus: draft\n")
    result = FrontMatterTags.replace(text, %w[a c])

    assert_equal doc("title: Hello\ntags: [\"a\", \"c\"]\nstatus: draft\n"), result
  end

  test "replaces a block list, indented or flush left" do
    indented = doc("title: x\ntags:\n  - a\n  - b\nstatus: draft\n")
    flush = doc("title: x\ntags:\n- a\n- b\nstatus: draft\n")

    [ indented, flush ].each do |text|
      result = FrontMatterTags.replace(text, %w[b])
      assert_equal doc("title: x\ntags: [\"b\"]\nstatus: draft\n"), result
    end
  end

  test "adds a tags line when there is none, and leaves the file alone when there's nothing to add" do
    assert_equal doc("title: x\ntags: [\"new\"]\n"), FrontMatterTags.replace(doc("title: x\n"), %w[new])
    assert_equal doc("title: x\n"), FrontMatterTags.replace(doc("title: x\n"), [])
  end

  test "an emptied list is written as []" do
    assert_equal doc("tags: []\ntitle: x\n"), FrontMatterTags.replace(doc("tags: [\"a\"]\ntitle: x\n"), [])
  end

  test "keeps the body, including a --- line inside it" do
    text = doc("tags: [\"a\"]\n", "Intro\n\n---\n\nMore\n")
    result = FrontMatterTags.replace(text, %w[b])

    assert result.end_with?("---\nIntro\n\n---\n\nMore\n")
    assert_equal %w[b], FrontMatterTags.read(result)
  end

  test "tags YAML would misread are quoted and read back unchanged" do
    tags = [ "yes", "a: b", "#hash", "it's", "émigré" ]
    result = FrontMatterTags.replace(doc("title: x\n"), tags)

    assert_equal tags, FrontMatterTags.read(result)
  end

  test "no front matter means no change" do
    assert_nil FrontMatterTags.replace("Just text", %w[a])
  end
end
