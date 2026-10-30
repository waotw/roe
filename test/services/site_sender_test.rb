# frozen_string_literal: true

require "test_helper"

# A site with author_email set to "" sent every email as From: " <>", which
# Postmark rejects. A MISSING key worked, because the old code used a bare ||
# and only nil reached the fallback.
class SiteSenderTest < ActiveSupport::TestCase
  # Writes site.yml, which is what SiteConfig.get reads. test_helper reseeds
  # the file before every test, so this can't leak.
  def stub_site(values) = with_site_config(values)

  test "an empty author_email counts as no address" do
    stub_site("author_email" => "", "author" => "Someone")

    refute_predicate SiteSender, :configured?
    assert_nil SiteSender.address
    assert_nil SiteSender.from_header
  end

  test "a missing author_email counts as no address" do
    stub_site({})

    refute_predicate SiteSender, :configured?
    assert_nil SiteSender.from_header
  end

  test "an address and a name make a From header" do
    stub_site("author_email" => "hello@example.com", "author" => "Ben")

    assert_predicate SiteSender, :configured?
    assert_equal "Ben <hello@example.com>", SiteSender.from_header
  end

  test "a blank name gives a bare address rather than a leading space" do
    stub_site("author_email" => "hello@example.com", "author" => "", "title" => "")

    assert_equal "hello@example.com", SiteSender.from_header
  end

  test "the site title stands in for a missing author name" do
    stub_site("author_email" => "hello@example.com", "author" => "", "title" => "My Site")

    assert_equal "My Site <hello@example.com>", SiteSender.from_header
  end

  test "there is no stand-in address" do
    # Postmark rejects any From it hasn't verified, so a placeholder can't
    # rescue a send — it only replaces a clear error with a confusing one.
    stub_site("author_email" => "")

    assert_nil SiteSender.address
    refute_includes SiteSender::MISSING, "example.com"
  end
end
