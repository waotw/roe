require "test_helper"

# PostmarkAccountSetup drives Postmark's Account + Server APIs to create/reuse
# servers, read back tokens, set up webhooks, and read sender signatures. It
# must NEVER persist the account token — that's the caller's job, and only in
# production. Here we stub Net::HTTP at the request level (mocha, matching
# PostmarkServiceTest) and assert the API contract + the token-handling rules.
class PostmarkAccountSetupTest < ActiveSupport::TestCase
  # A tiny router: map "METHOD /path" (path without querystring) to a canned
  # [code, body] so one stubbed http object answers every call in a run.
  def stub_http(routes)
    http = mock("http")
    http.stubs(:use_ssl=)
    http.instance_variable_set(:@routes, routes)
    def http.request(req)
      code, body = @routes["#{req.method} #{req.path.split('?').first}"] ||
                   [ "404", '{"Message":"unrouted"}' ]
      r = Object.new
      r.define_singleton_method(:code) { code }
      r.define_singleton_method(:body) { body }
      r
    end
    Net::HTTP.stubs(:new).returns(http)
    http
  end

  setup do
    @setup = PostmarkAccountSetup.new("acct-token")
  end

  test "list_servers flags the default server by its stock name" do
    stub_http("GET /servers" => [ "200", {
      "TotalCount" => 2,
      "Servers" => [
        { "ID" => 1, "Name" => "My First Server", "DeliveryType" => "Live", "ApiTokens" => [ "t1" ] },
        { "ID" => 2, "Name" => "Acme - Production", "DeliveryType" => "Live", "ApiTokens" => [ "t2" ] }
      ]
    }.to_json ])

    servers = @setup.list_servers
    assert_equal 2, servers.size
    assert servers.find { |s| s[:id] == 1 }[:default], "My First Server is the default"
    assert_not servers.find { |s| s[:id] == 2 }[:default], "a named server is not the default"
  end

  test "ensure_server creates a sandbox server and reads back its token" do
    stub_http("POST /servers" => [ "200", {
      "ID" => 9, "Name" => "Acme - Sandbox", "DeliveryType" => "Sandbox", "ApiTokens" => [ "sbx-token" ]
    }.to_json ])

    server = @setup.ensure_server(kind: :sandbox, name: "Acme - Sandbox")
    assert server.created
    assert_equal "sbx-token", server.token
    assert_equal "Sandbox", server.delivery_type
  end

  test "ensure_server reuses an existing server without creating one" do
    stub_http("GET /servers/2" => [ "200", {
      "ID" => 2, "Name" => "Acme - Production", "DeliveryType" => "Live", "ApiTokens" => [ "live-token" ]
    }.to_json ])

    server = @setup.ensure_server(kind: :live, name: "ignored", reuse_id: "2")
    assert_not server.created
    assert_equal "live-token", server.token
  end

  test "ensure_webhook creates a webhook on both streams when none matches" do
    stub_http(
      "GET /webhooks"  => [ "200", { "Webhooks" => [] }.to_json ],
      "POST /webhooks" => [ "200", { "ID" => 55 }.to_json ]
    )
    result = @setup.ensure_webhook("srv-token", "https://acme.com/webhooks/postmark/abc")
    assert result[:ok]
    assert_equal %w[outbound broadcast], result[:streams].keys, "both message streams get a webhook"
    assert result[:streams]["outbound"][:ok]
    assert result[:streams]["broadcast"][:ok]
  end

  test "ensure_webhook reuses an existing webhook with the same URL" do
    url = "https://acme.com/webhooks/postmark/abc"
    stub_http("GET /webhooks" => [ "200", { "Webhooks" => [ { "ID" => 7, "Url" => url } ] }.to_json ])
    result = @setup.ensure_webhook("srv-token", url)
    assert result[:ok]
    assert result[:streams]["outbound"][:reused]
    assert result[:streams]["broadcast"][:reused]
  end

  test "ensure_webhook returns an error (never raises) for a blank URL" do
    result = @setup.ensure_webhook("srv-token", "")
    assert_not result[:ok]
    assert_match(/reachable/i, result[:error])
  end

  test "a non-2xx response surfaces Postmark's Message" do
    stub_http("POST /servers" => [ "422", { "ErrorCode" => 402, "Message" => "Server names must be unique." }.to_json ])
    error = assert_raises(PostmarkAccountSetup::Error) do
      @setup.ensure_server(kind: :live, name: "dupe")
    end
    assert_match(/unique/, error.message)
  end

  test "sender_signatures reports confirmed state" do
    stub_http("GET /senders" => [ "200", {
      "SenderSignatures" => [
        { "ID" => 1, "EmailAddress" => "a@acme.com", "Name" => "A", "Domain" => "acme.com", "Confirmed" => true },
        { "ID" => 2, "EmailAddress" => "b@acme.com", "Name" => "B", "Domain" => "acme.com", "Confirmed" => false }
      ]
    }.to_json ])
    sigs = @setup.sender_signatures
    assert_equal 2, sigs.size
    assert sigs.first[:confirmed]
    assert_not sigs.last[:confirmed]
  end

  test "sender_detail reads DKIM and return-path for the matching address" do
    stub_http(
      "GET /senders"   => [ "200", { "SenderSignatures" => [
        { "ID" => 9, "EmailAddress" => "me@acme.com", "Confirmed" => true }
      ] }.to_json ],
      "GET /senders/9" => [ "200", {
        "EmailAddress" => "me@acme.com", "Confirmed" => true,
        "DKIMVerified" => true, "ReturnPathDomainVerified" => false
      }.to_json ]
    )
    d = @setup.sender_detail("ME@acme.com") # case-insensitive match
    assert d[:confirmed]
    assert d[:dkim_verified]
    assert_not d[:return_path_verified]
  end

  test "sender_detail is nil when no signature matches" do
    stub_http("GET /senders" => [ "200", { "SenderSignatures" => [] }.to_json ])
    assert_nil @setup.sender_detail("nobody@acme.com")
  end
end
