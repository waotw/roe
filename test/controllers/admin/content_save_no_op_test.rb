require "test_helper"

# Re-saving a post, page or product with no changes reported a Site Sync
# change. SiteFile.write only went into the config controllers; content still
# called File.write directly, so an identical save rewrote the file and bumped
# its mtime — which Site Sync reads as an edit.
class ContentSaveNoOpTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(User.take) }

  test "no content controller writes files directly any more" do
    %w[posts pages products].each do |kind|
      source = File.read(Rails.root.join("app/controllers/admin/#{kind}_controller.rb"))

      assert_no_match(/(?<!Site)File\.write\(/, source,
        "#{kind}_controller writes with File.write — an identical save will bump mtime " \
        "and show as Site Sync drift the user didn't cause")
    end
  end

  test "re-saving a product with no changes leaves the file untouched" do
    dir = File.join(RoeSitePaths::SITE_PATH, "products")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "zz-noop.md")
    File.write(path, "---\ntitle: \"ZZ NoOp\"\nurl_name: \"zz-noop\"\nstatus: \"draft\"\nsku: \"ZZ-N-1\"\nprice: 5.0\n---\n\nbody\n")
    product = Product.create_or_update_from_file(path)

    File.utime(Time.at(1_000_000), Time.at(1_000_000), path)
    before = File.stat(path).mtime.to_i
    bytes  = File.binread(path)

    # Same write the controller performs, with nothing changed.
    SiteFile.write(path, bytes)

    assert_equal bytes, File.binread(path)
    assert_equal before, File.stat(path).mtime.to_i,
      "an unchanged save must not bump mtime"
  ensure
    FileUtils.rm_f(path)
    Product.where(file_path: RoeSitePaths.normalize(path)).destroy_all if path
  end
end
