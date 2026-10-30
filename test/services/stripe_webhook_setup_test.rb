require "test_helper"

class StripeWebhookSetupTest < ActiveSupport::TestCase
  # Fake Stripe::WebhookEndpoint so no network is touched.
  class FakeEndpoint
    attr_reader :id, :url, :secret
    def initialize(id:, url:, secret: nil)
      @id = id; @url = url; @secret = secret
    end
  end

  ROE_URL = "https://example.com/webhooks/stripe".freeze

  # Stub Stripe::WebhookEndpoint.list to return an object whose
  # auto_paging_each yields the given endpoints; create returns a fresh
  # endpoint with a secret and records the params; delete records the id.
  def stub_stripe(existing: [])
    list_obj = Object.new
    list_obj.define_singleton_method(:auto_paging_each) { |&blk| existing.each(&blk) }
    Stripe::WebhookEndpoint.stubs(:list).returns(list_obj)

    @created = []
    Stripe::WebhookEndpoint.stubs(:create).with do |params, _opts|
      @created << params
      true
    end.returns(FakeEndpoint.new(id: "we_new", url: ROE_URL, secret: "whsec_fresh123"))

    @deleted = []
    Stripe::WebhookEndpoint.stubs(:delete).with do |id, _p, _o|
      @deleted << id
      true
    end.returns(true)
  end

  test "creates an endpoint and captures the signing secret when none exists" do
    stub_stripe(existing: [])
    result = StripeWebhookSetup.new("sk_test_x").ensure_endpoint(ROE_URL)
    assert_equal "we_new", result[:id]
    assert_equal "whsec_fresh123", result[:signing_secret]
    assert_equal false, result[:recreated]
    assert_equal 1, @created.length
    assert_equal StripeWebhookSetup::ENABLED_EVENTS, @created.first[:enabled_events]
    assert_empty @deleted
  end

  test "deletes and recreates an existing endpoint to obtain a usable secret" do
    existing = FakeEndpoint.new(id: "we_old", url: ROE_URL)
    stub_stripe(existing: [ existing ])
    result = StripeWebhookSetup.new("sk_test_x").ensure_endpoint(ROE_URL)
    assert_equal true, result[:recreated]
    assert_equal [ "we_old" ], @deleted
    assert_equal "whsec_fresh123", result[:signing_secret]
  end

  test "endpoint_registered? is true only when a matching URL exists" do
    stub_stripe(existing: [ FakeEndpoint.new(id: "we_1", url: ROE_URL) ])
    assert StripeWebhookSetup.new("sk_test_x").endpoint_registered?(ROE_URL)

    stub_stripe(existing: [])
    assert_not StripeWebhookSetup.new("sk_test_x").endpoint_registered?(ROE_URL)
  end

  test "raises with a friendly message when no key is given" do
    err = assert_raises(StripeWebhookSetup::Error) { StripeWebhookSetup.new("") }
    assert_match(/secret key is required/i, err.message)
  end
end
