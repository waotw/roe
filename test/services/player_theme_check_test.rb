require "test_helper"

class PlayerThemeCheckTest < ActiveSupport::TestCase
  setup do
    @dir = File.join(RoeSitePaths::SITE_PATH, "theme")
    FileUtils.mkdir_p(@dir)
    @path = File.join(@dir, "zz-check.css")
    SiteConfig.stubs(:get).returns(nil)
    SiteConfig.stubs(:get).with("theme.active").returns("zz-check")
  end

  teardown { FileUtils.rm_f(@path) }

  test "a theme with the card's styles is styled" do
    File.write(@path, ".player-toggle::before { content: \"\\25B6\"; }\n")
    assert PlayerThemeCheck.styled?
  end

  test "a theme without them isn't, and it notices when the file changes" do
    File.write(@path, "body { color: red; }\n")
    assert_not PlayerThemeCheck.styled?

    File.write(@path, "body { color: red; }\n.player-toggle { border: 0; }\n")
    File.utime(Time.now + 5, Time.now + 5, @path)
    assert PlayerThemeCheck.styled?
  end

  test "a theme Roe ships but the site hasn't copied counts as styled" do
    SiteConfig.stubs(:get).with("theme.active").returns("default")
    FileUtils.mv(File.join(@dir, "default.css"), "#{@path}.bak") if File.file?(File.join(@dir, "default.css"))
    assert PlayerThemeCheck.styled?
  ensure
    FileUtils.mv("#{@path}.bak", File.join(@dir, "default.css")) if File.file?("#{@path}.bak")
  end
end
