require "test_helper"
require "digest"

module SiteSync
  # Exchange.upload_large_file — the sending half of chunked uploads — run
  # against the real receiving endpoint in this app (Rack::Test underneath
  # Net::HTTP), so both halves are tested together: pieces in order, a
  # resume after an interruption, and the finished file in place.
  class ChunkedUploadSendTest < ActionDispatch::IntegrationTest
    SITE = RoeSitePaths::SITE_PATH

    setup do
      @rel = "media/video/variants/send-720p.mp4"
      @src_root = Dir.mktmpdir("chunk-src")
      @data = Random.bytes(50_000)
      FileUtils.mkdir_p(File.join(@src_root, File.dirname(@rel)))
      File.binwrite(File.join(@src_root, @rel), @data)

      Exchange.stubs(:can_call_peer?).returns(true)
      Exchange.stubs(:peer_url).returns("http://www.example.com")
      SyncConfig.current.update!(token: SecureRandom.hex(32))
      Exchange.stubs(:token).returns(SyncConfig.current.token)
      stub_const(Exchange, :CHUNK_BYTES, 16_000)

      # Route Net::HTTP to this app's integration session.
      session = self
      fake = Object.new
      fake.define_singleton_method(:request) do |req|
        session.public_send(:post, req.path, params: req.body.to_s,
                                             headers: { "Authorization" => req["Authorization"], "Content-Type" => req["Content-Type"] })
        res = session.response
        klass = Net::HTTPResponse::CODE_TO_OBJ[res.status.to_s] || Net::HTTPUnknownResponse
        out = klass.new("1.1", res.status.to_s, res.message.to_s)
        out.instance_variable_set(:@body, res.body)
        out.instance_variable_set(:@read, true)
        @sent ||= 0
        @sent += 1
        out
      end
      fake.define_singleton_method(:sent) { @sent.to_i }
      @fake = fake
      Net::HTTP.any_instance.stubs(:start).yields(fake)
    end

    teardown do
      FileUtils.rm_rf(@src_root)
      FileUtils.rm_f(File.join(SITE, @rel))
      FileUtils.rm_rf(File.join(SITE, ".sync-uploads"))
      Array(@restore).each { |mod, name, v| mod.send(:remove_const, name); mod.const_set(name, v) }
    end

    def stub_const(mod, name, value)
      (@restore ||= []) << [ mod, name, mod.const_get(name) ]
      mod.send(:remove_const, name)
      mod.const_set(name, value)
    end

    test "sends the file in pieces and the live side ends up with an exact copy" do
      progress = []
      Exchange.upload_large_file(@rel, root: @src_root, on_bytes: ->(n) { progress << n })

      assert_equal @data, File.binread(File.join(SITE, @rel))
      assert_equal [ 16_000, 32_000, 48_000, 50_000 ], progress
      assert_equal 5, @fake.sent, "4 pieces + finish"
    end

    test "picks up where an interrupted send stopped" do
      # A previous run got the first two pieces across, then died.
      id = Digest::SHA256.hexdigest([ @rel, @data.bytesize, File.mtime(File.join(@src_root, @rel)).to_i, Digest::SHA256.hexdigest(@data) ].join("\0"))[0, 32]
      FileUtils.mkdir_p(File.join(SITE, ".sync-uploads"))
      File.binwrite(File.join(SITE, ".sync-uploads", "#{id}.part"), @data[0, 32_000])

      Exchange.upload_large_file(@rel, root: @src_root)

      assert_equal @data, File.binread(File.join(SITE, @rel))
      # First piece is answered 409 "received: 32000", then the rest: 1 + 2 + finish.
      assert_equal 4, @fake.sent
    end
  end
end
