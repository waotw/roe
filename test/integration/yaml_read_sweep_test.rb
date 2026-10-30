require "test_helper"

# Config files must never be read with a bare YAML.load_file. Bootsnap caches
# that on (mtime, size), and mtime is whole-second on some filesystems, so a
# change of the same length inside one second is read as the old contents.
# Where the read is changed and written back, that throws away the newer save.
# SiteFile.read_yaml is the reader to use (see test/services/site_file_test.rb).
class YamlReadSweepTest < ActionDispatch::IntegrationTest
  # Bootsnap only intercepts load_file and unsafe_load_file, and only when
  # called with no options it doesn't support — passing permitted_classes:
  # skips its cache, so those calls are safe.
  test "no bare YAML.load_file is left in the app" do
    bare = Dir.glob(Rails.root.join("{app,lib,config,bin}/**/*.{rb,rake}")).flat_map do |file|
      File.readlines(file).each_with_index.filter_map do |line, i|
        next if line.strip.start_with?("#")
        next unless line.match?(/\b(YAML|Psych)\.(unsafe_)?load_file\b/)
        next if line.include?("permitted_classes")

        "#{file.delete_prefix("#{Rails.root}/")}:#{i + 1}: #{line.strip}"
      end
    end

    assert_empty bare, "read these with SiteFile.read_yaml instead:\n#{bare.join("\n")}"
  end

  # The riskiest of the callers swept: switching the update channel reads
  # site.yml, sets one key and writes the whole file back. A stale read there
  # undoes whatever was saved to site.yml just before.
  test "switching the update channel keeps a same-second, same-length save to site.yml" do
    sign_in_as(users(:one))
    original = File.exist?(SiteConfig::SITE_FILE) ? File.read(SiteConfig::SITE_FILE) : nil

    File.write(SiteConfig::SITE_FILE, "title: aaa\nupdate_channel: stable\n")
    YAML.load_file(SiteConfig::SITE_FILE) # the earlier read bootsnap remembers
    File.write(SiteConfig::SITE_FILE, "title: bbb\nupdate_channel: stable\n")

    post admin_update_channel_path, params: { channel: "nightly" }

    saved = YAML.load(File.read(SiteConfig::SITE_FILE))
    assert_equal "nightly", saved["update_channel"]
    assert_equal "bbb", saved["title"], "the save just before the switch was undone"
  ensure
    original ? File.write(SiteConfig::SITE_FILE, original) : FileUtils.rm_f(SiteConfig::SITE_FILE)
  end
end
