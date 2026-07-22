require "test_helper"
require "net/ftp"

# Guards the FTPS pusher's TLS wiring. Net::FTP has no `ssl=` setter — TLS
# can only be configured through the constructor's `ssl:` option. An earlier
# version called `ftp.ssl = ...` and blew up (NoMethodError) the first time
# it ran against a real host, with zero test coverage to catch it.
class StaticSiteSync::Pushers::FtpsTest < ActiveSupport::TestCase
  def build_pusher(config)
    StaticSiteSync::Pushers::Ftps.new(config: config, root: Pathname.new("/tmp"))
  end

  def stub_config(verify_tls: true)
    stub("config",
      host: "ftp.example.com",
      port: 21,
      username: "user",
      password: "pass",
      remote_path: "public_html",
      verify_tls: verify_tls)
  end

  test "configures TLS through the constructor, never a ssl= setter" do
    ftp = mock("net_ftp")
    ftp.expects(:passive=).with(true)
    ftp.expects(:open_timeout=).with(30)
    ftp.expects(:read_timeout=).with(60)
    ftp.expects(:connect).with("ftp.example.com", 21)
    ftp.expects(:login).with("user", "pass")
    ftp.expects(:chdir).with("public_html")
    ftp.stubs(:close)

    # The regression guard: TLS must arrive as an :ssl constructor option.
    # A strict mock also fails loudly if anyone reintroduces `ftp.ssl = ...`,
    # since no `ssl=` expectation is set on it.
    Net::FTP.expects(:new)
            .with(nil, has_entry(:ssl, instance_of(Hash)))
            .returns(ftp)

    assert build_pusher(stub_config).test_connection
  end

  test "verifies the peer certificate when verify_tls is on" do
    opts = build_pusher(stub_config(verify_tls: true)).send(:ssl_context_options)
    assert_equal OpenSSL::SSL::VERIFY_PEER, opts[:verify_mode]
  end

  test "skips certificate verification when verify_tls is off" do
    opts = build_pusher(stub_config(verify_tls: false)).send(:ssl_context_options)
    assert_equal OpenSSL::SSL::VERIFY_NONE, opts[:verify_mode]
  end

  test "a name-resolution failure surfaces a DNS-propagation hint" do
    config = stub("config", host: "ftp.example.com", port: 21, username: "u", password: "p",
                  verify_tls: true, remote_path: "public_html")
    ftp = mock("net_ftp")
    ftp.stubs(:passive=); ftp.stubs(:open_timeout=); ftp.stubs(:read_timeout=); ftp.stubs(:close)
    ftp.expects(:connect).raises(SocketError, "getaddrinfo: nodename nor servname provided")
    Net::FTP.expects(:new).returns(ftp)
    err = assert_raises(StaticSiteSync::Pusher::ConnectionError) { build_pusher(config).test_connection }
    assert_match(/Couldn't find ftp\.example\.com/, err.message)
    assert_match(/propagating/, err.message)
  end
end
