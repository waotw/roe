# frozen_string_literal: true

require "test_helper"

# Exchange.rewind_peer_ledger! asks live to record the rewound entries. A live
# site on an older Roe has no such endpoint: that's not an error, its record
# just stays as it was.
class SiteSync::RewindPeerLedgerTest < ActiveSupport::TestCase
  setup do
    SiteSync::Exchange.stubs(:can_call_peer?).returns(true)
    SiteSync::Exchange.stubs(:peer_url).returns("https://live.example")
    SiteSync::Exchange.stubs(:sleep)
  end

  def response(klass, code, body, type)
    r = klass.new("1.1", code, "")
    r["Content-Type"] = type
    r.instance_variable_set(:@read, true)
    r.instance_variable_set(:@body, body)
    r
  end

  test "sends the entries and reports success" do
    sent = nil
    SiteSync::Exchange.stubs(:post_to_peer).with { |uri, body| sent = [ uri.path, JSON.parse(body) ] }
                      .returns(response(Net::HTTPOK, "200", "{\"ok\":true}", "application/json"))

    assert SiteSync::Exchange.rewind_peer_ledger!({ "posts/a.md" => { "size" => 1, "mtime" => 2 }, "posts/b.md" => nil })
    assert_equal "/api/site_sync/rewind_ledger", sent[0]
    assert_equal({ "posts/a.md" => { "size" => 1, "mtime" => 2 }, "posts/b.md" => nil }, sent[1]["files"])
  end

  test "an older live without the endpoint is skipped, not retried" do
    SiteSync::Exchange.expects(:post_to_peer).once
                      .returns(response(Net::HTTPNotFound, "404", "<html>Not Found</html>", "text/html"))

    assert_not SiteSync::Exchange.rewind_peer_ledger!({ "posts/a.md" => nil })
  end

  test "nothing is sent when this side doesn't call live" do
    SiteSync::Exchange.stubs(:can_call_peer?).returns(false)
    SiteSync::Exchange.expects(:post_to_peer).never

    assert_not SiteSync::Exchange.rewind_peer_ledger!({ "posts/a.md" => nil })
  end
end
