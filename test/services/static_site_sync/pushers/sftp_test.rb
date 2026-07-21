require "test_helper"
require "net/sftp"

class StaticSiteSync::Pushers::SftpTest < ActiveSupport::TestCase
  def build_pusher(config)
    StaticSiteSync::Pushers::Sftp.new(config: config, root: Pathname.new("/tmp"))
  end

  # Regression: Net::SFTP.start's return value with a block is NOT the
  # block's result, so with_session must capture it — otherwise push!
  # returns nil and the job crashes recording the manifest.
  test "with_session returns the block's value even when Net::SFTP.start returns nil" do
    config = stub("config", host: "h", username: "u", port: 22,
                  auth_mode_ssh_key?: false, password: "pw")
    Net::SFTP.expects(:start).yields(mock("sftp")).returns(nil)
    assert_equal :block_value, build_pusher(config).send(:with_session) { |_sftp| :block_value }
  end

  test "ssh_options forwards the passphrase and normalizes CRLF line endings in the key" do
    config = stub("config",
      auth_mode_ssh_key?: true,
      ssh_private_key: "FAKE-KEY-LINE-1\r\nFAKE-KEY-LINE-2",
      ssh_key_passphrase: "FAKE-PASSPHRASE",
      port: 22)
    opts = build_pusher(config).send(:ssh_options)

    assert_equal "FAKE-PASSPHRASE", opts[:passphrase]
    # CRLF collapsed to LF, and a trailing newline guaranteed.
    assert_equal [ "FAKE-KEY-LINE-1\nFAKE-KEY-LINE-2\n" ], opts[:key_data]
    assert opts[:keys_only]
  end

  test "ssh_options omits the passphrase when none is set" do
    config = stub("config",
      auth_mode_ssh_key?: true,
      ssh_private_key: "FAKE-KEY",
      ssh_key_passphrase: "",
      port: 22)
    assert_nil build_pusher(config).send(:ssh_options)[:passphrase]
  end

  test "ssh_options uses password auth when auth_mode is password" do
    config = stub("config", auth_mode_ssh_key?: false, password: "pw", port: 22)
    opts = build_pusher(config).send(:ssh_options)

    assert_equal "pw", opts[:password]
    assert_equal [ "password" ], opts[:auth_methods]
    assert_nil opts[:key_data]
  end
end
