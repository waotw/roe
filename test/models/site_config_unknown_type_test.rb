# frozen_string_literal: true

require "test_helper"

# An unrecognised config type used to resolve to site.yml, so asking for
# something this class doesn't manage got the site config back instead of an
# error. Two things were already living in that gap — every `integrations/*`
# call and ContentWatcher's handling of custom_code.yml / development.yml —
# and both were invisible because the fallback looked like an answer.
class SiteConfigUnknownTypeTest < ActiveSupport::TestCase
  def path_for(type) = SiteConfig.send(:file_path_for, type)

  test "the types this class manages still resolve" do
    {
      "site"            => "site.yml",
      "content"         => "content.yml",
      "fonts"           => "fonts.yml",
      "deploy"          => "deploy.yml",
      "security"        => "security.yml",
      "features/store"  => "store.yml",
      "defaults/cards"  => "cards.yml"
    }.each do |type, filename|
      assert_equal filename, File.basename(path_for(type).to_s), "#{type} stopped resolving"
    end
  end

  test "an unknown type resolves to nothing, not to site.yml" do
    [ "notes", "typo/thing", "integrations/stripe", "custom_code", "development", "" ].each do |type|
      assert_nil path_for(type), "#{type.inspect} still falls back to a real file"
    end
  end

  test "reading an unknown type is nil, not the site config" do
    site = SiteConfig.current("site")

    assert_not_nil site, "precondition — the site config exists"
    assert_nil SiteConfig.current("notes")
    assert_nil SiteConfig.current("integrations/stripe"),
      "this returned the site config, which is what SiteConfig.integration would have served"
  end

  test "syncing an unknown type does nothing rather than loading site.yml" do
    before = SiteConfig.current("site")&.config

    assert_nil SiteConfig.sync_from_file("integrations/stripe")
    assert_nil SiteConfig.sync_from_file("notes")

    assert_equal before, SiteConfig.current("site")&.config, "the site config was touched"
  end

  # ContentWatcher hands this the basename of any .yml dropped into
  # system/global/, so an unknown name has to be survivable, not fatal.
  test "an unknown type is survivable" do
    assert_nothing_raised do
      SiteConfig.current("whatever-a-user-dropped-in")
      SiteConfig.sync_from_file("whatever-a-user-dropped-in")
    end
  end

  test "the default type is still site" do
    assert_equal SiteConfig.current("site")&.id, SiteConfig.current&.id
  end
end
