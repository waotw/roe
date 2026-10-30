require "test_helper"

# How `roe install` and the Tools pages choose a way to install a tool:
# each tool lists its install methods best first, and the package manager
# is skipped (or flagged) when Homebrew has no ready-made build for this
# macOS. Platforms are built by hand, so none of this depends on the
# machine running the tests.
class ManagedToolsInstallMethodsTest < ActiveSupport::TestCase
  def platform(os: :macos, manager: :brew, arch: :arm64, version: "14.8.5", bottle: true)
    ManagedTools::Platform.new(os: os, package_manager: manager, arch: arch, os_version: version).tap do |p|
      p.stubs(:homebrew_bottle?).returns(bottle)
    end
  end

  setup do
    @ffmpeg = ManagedTools::Ffmpeg.new
    ManagedTools::Platform.stubs(:mise_path).returns("/x/mise")
  end

  test "ffmpeg prefers Homebrew when it has a ready-made build" do
    methods = @ffmpeg.install_methods(platform(bottle: true))

    assert_equal %i[package_manager download mise], methods.map(&:key)
    assert methods.all?(&:usable?)
    assert_equal "brew install ffmpeg", @ffmpeg.recommended_install(platform(bottle: true)).command
  end

  test "ffmpeg skips Homebrew on a macOS it no longer builds for, and recommends the download" do
    p = platform(version: "14.8.5", bottle: false)
    brew, download, mise = @ffmpeg.install_methods(p)

    assert_not brew.usable?
    assert_match(/no longer has ready-made builds for macOS 14/, brew.reason)
    assert download.usable?
    assert_match(/about 130 MB/, download.detail)
    assert mise.usable?
    assert_equal "mise use -g conda:ffmpeg", mise.command
    assert_equal :download, @ffmpeg.recommended_install(p).key
  end

  test "libvips still offers Homebrew without a ready-made build — slow, but the only way" do
    brew = ManagedTools::Libvips.new.install_methods(platform(bottle: false)).first

    assert brew.usable?
    assert_match(/build libvips from source/, brew.reason)
  end

  test "apt on Linux needs sudo; the download and mise don't" do
    p = platform(os: :linux, manager: :apt, arch: :x86_64, version: "Ubuntu 24.04 LTS")
    apt, download, mise = @ffmpeg.install_methods(p)

    assert apt.sudo
    assert_match(/apt-get install -y ffmpeg/, apt.command)
    assert_not download.sudo
    assert_not mise.sudo
  end

  test "no download offered where there's no build, and no mise when it isn't installed" do
    ManagedTools::Platform.stubs(:mise_path).returns(nil)
    p = platform(os: :linux, manager: nil, arch: nil, version: nil)
    methods = @ffmpeg.install_methods(p)

    assert_not methods.any?(&:usable?)
    assert_nil @ffmpeg.recommended_install(p)
    assert_match(/No package manager/, methods[0].reason)
    assert_match(/no ready-made download/, methods[1].reason)
    assert_match(/mise isn't installed/, methods[2].reason)
  end

  test "status carries the methods and the recommended one for the Tools page" do
    @ffmpeg.stubs(:installed?).returns(false)
    status = @ffmpeg.status(platform(bottle: false))

    assert_equal 3, status[:install_methods].size
    assert_equal :download, status[:install_method][:key]
    assert_nil status[:install_command] # a download has no command to copy
    assert_equal "macOS 14.8.5 · Apple Silicon", status[:system_label]
  end

  test "the Stripe CLI only offers Homebrew, and explains why not elsewhere" do
    stripe = ManagedTools::StripeCli.new
    assert_equal "brew install stripe/stripe-cli/stripe", stripe.install_command(platform)

    apt = stripe.install_methods(platform(os: :linux, manager: :apt)).first
    assert_not apt.usable?
    assert_match(/Stripe's own package source/, apt.reason)
  end

  test "system_label names the OS version and chip" do
    assert_equal "macOS 14.8.5 · Apple Silicon", platform.system_label
    assert_equal "macOS 13.6 · Intel", platform(version: "13.6", arch: :x86_64).system_label
    assert_equal "Ubuntu 24.04 LTS · arm64", platform(os: :linux, manager: :apt, version: "Ubuntu 24.04 LTS").system_label
  end
end

# Platform#homebrew_bottle? asks `brew info --json=v2`, which lists only the
# bottles that fit this machine. An empty list means Homebrew would build
# from source.
class ManagedToolsHomebrewBottleTest < ActiveSupport::TestCase
  OK = Struct.new(:ok) { def success? = ok }

  setup do
    ManagedTools::Platform.bottle_cache.clear
    ManagedTools::Platform.stubs(:find_executable).with("brew").returns("/x/brew")
    @platform = ManagedTools::Platform.new(os: :macos, package_manager: :brew, arch: :arm64, os_version: "14.8.5")
  end

  teardown { ManagedTools::Platform.bottle_cache.clear }

  def brew_says(bottle)
    json = { formulae: [ { name: "ffmpeg", bottle: bottle } ] }.to_json
    ManagedTools::Platform.stubs(:run).returns([ json, "", OK.new(true) ])
  end

  test "true when there's a bottle for this machine" do
    brew_says(stable: { files: { arm64_sonoma: { url: "x" } } })
    assert_equal true, @platform.homebrew_bottle?("ffmpeg")
  end

  test "false when Homebrew lists none — an unsupported macOS" do
    brew_says({})
    assert_equal false, @platform.homebrew_bottle?("ffmpeg")
  end

  test "nil when brew fails, so the method isn't wrongly skipped" do
    ManagedTools::Platform.stubs(:run).returns([ "", "Error", OK.new(false) ])
    assert_nil @platform.homebrew_bottle?("ffmpeg")
  end

  test "answers are cached, so the Tools page doesn't run brew every time" do
    brew_says({})
    ManagedTools::Platform.expects(:run).once.returns([ { formulae: [ { bottle: {} } ] }.to_json, "", OK.new(true) ])
    ManagedTools::Platform.bottle_cache.clear

    2.times { @platform.homebrew_bottle?("ffmpeg") }
  end

  test "not asked at all without Homebrew" do
    linux = ManagedTools::Platform.new(os: :linux, package_manager: :apt)
    ManagedTools::Platform.expects(:run).never
    assert_nil linux.homebrew_bottle?("ffmpeg")
  end
end

# The direct download: pinned files, checked against their SHA-256, unpacked
# into ~/.roe/tools/<tool>/<version>, and run once to prove they work. The
# network step is stubbed with zips built here, holding small shell scripts
# that answer `-version` like ffmpeg does.
class ManagedToolsDownloaderTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("roe-tools-test")
    @platform = ManagedTools::Platform.new(os: :macos, package_manager: :brew, arch: :arm64, os_version: "14.8.5")
    @zips = {}
  end

  teardown { FileUtils.rm_rf(@root) }

  # A zip holding one executable script named `name`.
  def zip_for(name, body: "#!/bin/sh\necho \"#{name} version 9.9.9\"\n")
    path = File.join(@root, "src-#{name}.zip")
    Zip::File.open(path, create: true) do |zip|
      zip.get_output_stream(name) { |f| f.write(body) }
      zip.get_output_stream("__MACOSX/._#{name}") { |f| f.write("junk") }
    end
    @zips["https://example.test/#{name}.zip"] = path
    { url: "https://example.test/#{name}.zip", sha256: Digest::SHA256.file(path).hexdigest }
  end

  def downloader(builds)
    d = ManagedTools::Downloader.new(tool: :ffmpeg, version: "9.9.9", builds: builds, root: @root)
    zips = @zips
    d.define_singleton_method(:download) { |url, dest, **| FileUtils.cp(zips.fetch(url), dest) }
    d
  end

  test "installs both programs into the versioned folder, ready to run" do
    d = downloader([ :macos, :arm64 ] => [ zip_for("ffmpeg"), zip_for("ffprobe") ])
    dir = d.install!(@platform)

    assert_equal File.join(@root, "ffmpeg", "9.9.9"), dir
    assert_equal %w[ffmpeg ffprobe], Dir.children(dir).sort
    assert File.executable?(File.join(dir, "ffprobe"))
  end

  test "a checksum mismatch is refused and leaves nothing behind" do
    bad = zip_for("ffmpeg").merge(sha256: "0" * 64)
    error = assert_raises(ManagedTools::Downloader::Error) { downloader([ :macos, :arm64 ] => [ bad ]).install!(@platform) }

    assert_match(/didn't match its checksum/, error.message)
    assert_equal [], Dir.children(File.join(@root, "ffmpeg"))
  end

  test "a program that won't run is refused" do
    broken = zip_for("ffmpeg", body: "#!/bin/sh\nexit 3\n")
    error = assert_raises(ManagedTools::Downloader::Error) { downloader([ :macos, :arm64 ] => [ broken ]).install!(@platform) }

    assert_match(/won't run on this computer/, error.message)
    assert_not File.exist?(File.join(@root, "ffmpeg", "9.9.9"))
  end

  test "no build for this computer says so" do
    error = assert_raises(ManagedTools::Downloader::Error) { downloader({}).install!(@platform) }
    assert_match(/no ready-made ffmpeg download for macOS 14.8.5/, error.message)
  end

  test "remove_other_versions! keeps only the current one" do
    FileUtils.mkdir_p(File.join(@root, "ffmpeg", "8.0.0"))
    d = downloader([ :macos, :arm64 ] => [ zip_for("ffmpeg") ])
    d.install!(@platform)
    d.remove_other_versions!

    assert_equal [ "9.9.9" ], Dir.children(File.join(@root, "ffmpeg"))
  end

  test "a downloaded ffmpeg is found and preferred, paired with its own ffprobe" do
    builds = { [ :macos, :arm64 ] => [ zip_for("ffmpeg"), zip_for("ffprobe") ] }
    tool = ManagedTools::Ffmpeg.new
    real = tool.downloader
    fake = downloader(builds)
    tool.stubs(:downloader).returns(fake)
    fake.install!(@platform)

    assert_equal File.join(fake.bin_dir, "ffmpeg"), tool.ffmpeg_path
    assert_equal File.join(fake.bin_dir, "ffprobe"), tool.ffprobe_path
    assert_equal ManagedTools::Ffmpeg::DOWNLOAD_VERSION, real.version
  end

  test "every pinned download is https with a SHA-256" do
    ManagedTools::Ffmpeg::DOWNLOAD_BUILDS.each do |(os, arch), files|
      assert_equal 2, files.size, "#{os}/#{arch} should have ffmpeg and ffprobe"
      files.each do |f|
        assert f[:url].start_with?("https://"), f[:url]
        assert_match(/\A\h{64}\z/, f[:sha256], f[:url])
        assert_includes f[:url], ManagedTools::Ffmpeg::DOWNLOAD_VERSION
      end
    end
  end
end
