# frozen_string_literal: true

require "test_helper"

# The limits themselves: what they default to, and every way a bad value in
# security.yml could otherwise lock people out.
class RateLimitsTest < ActiveSupport::TestCase
  def stub_security(hash)
    SiteConfig.stubs(:current).with("security").returns(OpenStruct.new(config: hash))
  end

  test "a site with no security.yml is still limited, on the defaults" do
    SiteConfig.stubs(:current).with("security").returns(nil)

    assert RateLimits.enabled?
    assert_equal 5, RateLimits.for(:magic_link)[:to]
    assert_equal 15.minutes, RateLimits.for(:magic_link)[:within]
  end

  test "the config overrides the defaults" do
    stub_security({ "limits" => { "magic_link" => { "to" => 99, "within" => 5 } } })

    assert_equal 99, RateLimits.for(:magic_link)[:to]
    assert_equal 5.minutes, RateLimits.for(:magic_link)[:within]
  end

  test "a limit the config doesn't mention keeps its default" do
    stub_security({ "limits" => { "magic_link" => { "to" => 99 } } })

    assert_equal 20, RateLimits.for(:signup)[:to]
    assert_equal 15.minutes, RateLimits.for(:magic_link)[:within], "the half it didn't set"
  end

  # A 0 would refuse everyone, which is the exact failure this is meant to
  # prevent. Read it as "not configured" rather than "allow nothing".
  test "a value that would lock everyone out is ignored" do
    [ 0, -1, "", "  ", "abc", nil ].each do |bad|
      stub_security({ "limits" => { "signup" => { "to" => bad, "within" => bad } } })

      assert_equal 20, RateLimits.for(:signup)[:to], "to: #{bad.inspect} should fall back"
      assert_equal 60.minutes, RateLimits.for(:signup)[:within], "within: #{bad.inspect} should fall back"
    end
  end

  test "an unreadable config falls back rather than raising" do
    SiteConfig.stubs(:current).raises(StandardError, "database gone")

    assert RateLimits.enabled?
    assert_equal 5, RateLimits.for(:magic_link)[:to]
  end

  test "limiting can be turned off" do
    stub_security({ "enabled" => false })
    assert_not RateLimits.enabled?

    stub_security({ "enabled" => true })
    assert RateLimits.enabled?
  end

  # Behind carrier-grade NAT an entire mobile network shares one address, so an
  # IP limit on sign-in emails would lock out strangers for each other's
  # behaviour. Flooding an inbox is abuse of that address, so that's the key.
  test "sign-in emails are counted per address, not per connection" do
    assert_equal :email, RateLimits.for(:magic_link)[:by]
  end

  # One URL holding the public corpus: a scraper needs one request, which is the
  # same request a reader makes. No number separates them, and the index carries
  # less than the pages it points at, so a limit would protect nothing.
  test "the search index is not rate limited" do
    assert_not_includes RateLimits.names, "search"
  end

  test "everything with no narrower handle falls back to the connection" do
    %i[signup checkout token].each do |name|
      assert_equal :ip, RateLimits.for(name)[:by], "#{name} has no narrower key available"
    end
  end
end
