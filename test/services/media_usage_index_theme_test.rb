# frozen_string_literal: true

require "test_helper"

# Media used in a theme's stylesheet counts as used: it gets a "Used in"
# link to the CSS editor, and it isn't listed as unused.
class MediaUsageIndexThemeTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  THEME_DIR = File.join(RoeSitePaths::SITE_PATH, "theme")

  setup do
    FileUtils.mkdir_p(THEME_DIR)
    @written = []
  end

  teardown { @written.each { |f| FileUtils.rm_f(f) } }

  def theme(name, css)
    path = File.join(THEME_DIR, "#{name}.css")
    File.write(path, css)
    @written << path
  end

  test "a url() in a theme is a use, linked to that theme's CSS editor at the file" do
    theme("zz-test-active", <<~CSS)
      body { background: url(/media/images/paper.jpg) repeat; }
      .hero { background-image: url("/media/images/hero shot.png"); }
    CSS

    index = MediaUsageIndex.new.build

    paper = index["/media/images/paper.jpg"]
    assert_equal 1, paper.size
    assert_equal "theme", paper.first[:kind]
    assert_equal "zz-test-active.css", paper.first[:label]
    assert_includes paper.first[:url], edit_admin_theme_path("zz-test-active")
    assert_includes paper.first[:url], "highlight=%2Fmedia%2Fimages%2Fpaper.jpg"

    assert_equal 1, index["/media/images/hero shot.png"].size, "a quoted path keeps its space"
    assert_empty index["/media/images/hero"], "and isn't also found cut short"
  end

  test "a path in a CSS comment is an example, not a use" do
    theme("zz-test-comment", <<~CSS)
      /* A video in a post: ![label](/media/video/clip.mp4) */
      .x { color: red; }
    CSS

    assert_empty MediaUsageIndex.new.build["/media/video/clip.mp4"]
  end

  test "every theme counts, not only the active one" do
    theme("zz-test-inactive", ".y { background: url('/media/images/old-bg.gif'); }")

    assert_equal [ "zz-test-inactive.css" ], MediaUsageIndex.new.build["/media/images/old-bg.gif"].map { |u| u[:label] }
  end
end
