require "test_helper"
require "fileutils"
require "digest"
require "socket"
require "webrick"

module SiteSync
  # Exchange.download_large_file over a real HTTP connection, against a
  # stand-in live site that answers the two endpoints the way
  # Api::SiteSync::ChunkedDownloadsController does — and can be told to
  # fail a piece, corrupt one, or not know the endpoint at all, so the
  # resume, checksum and old-live-site paths are exercised for real.
  class ExchangeLargeDownloadTest < ActiveSupport::TestCase
    def setup
      @data    = Random.bytes(2_500_000) # 3 pieces at a 1 MB piece size
      @mtime   = 1_700_000_000
      @scratch = Dir.mktmpdir("large-download")
      @staging = File.join(@scratch, "staging")
      @dest    = File.join(@scratch, "out", "clip.mov")
      @requests = []
      @fail_at_offset = nil
      @corrupt = false
      @no_endpoint = false

      start_server!
      Exchange.stubs(:can_call_peer?).returns(true)
      Exchange.stubs(:peer_url).returns("http://127.0.0.1:#{@port}")
      Exchange.stubs(:token).returns("t0ken")
      Exchange.stubs(:sleep) # retries back off; no need to wait in tests
      stub_const(Exchange, :CHUNK_BYTES, 1_000_000)
    end

    def teardown
      @server&.shutdown
      @thread&.join(2)
      FileUtils.rm_rf(@scratch)
      @restore_const&.call
    end

    def download(on_bytes: nil)
      Exchange.download_large_file("media/video/clip.mov", dest: @dest, staging_dir: @staging, on_bytes: on_bytes)
    end

    test "fetches every piece, checks it, and stamps the live modified time" do
      seen = []
      result = download(on_bytes: ->(n) { seen << n })

      assert_equal @data, File.binread(@dest)
      assert_equal @mtime, File.mtime(@dest).to_i
      assert_equal({ "size" => @data.bytesize, "mtime" => @mtime }, result)
      assert_equal [ 0, 1_000_000, 2_000_000, 2_500_000 ], seen
      assert_empty Dir.glob(File.join(@staging, "*")), "nothing left half-fetched"
    end

    test "after a failure, running again picks up where it stopped" do
      @fail_at_offset = 2_000_000 # every try at the last piece fails
      assert_raises(Exchange::ChunkedUploadError) { download }
      assert_not File.exist?(@dest), "nothing is written until the whole file is here"

      @fail_at_offset = nil
      @requests.clear
      download

      assert_equal @data, File.binread(@dest)
      offsets = @requests.select { |r| r[:path] == "chunk" }.map { |r| r[:offset] }
      assert_equal [ 2_000_000 ], offsets, "only the missing piece is fetched again"
    end

    test "a file that doesn't match its checksum is thrown away, not used" do
      @corrupt = true
      error = assert_raises(Exchange::ChunkedUploadError) { download }

      assert_match(/didn't arrive intact/, error.message)
      assert_not File.exist?(@dest)
      assert_empty Dir.glob(File.join(@staging, "*")), "a bad copy isn't resumed onto"
    end

    test "a live site without the endpoints says to deploy" do
      @no_endpoint = true
      error = assert_raises(Exchange::ChunkedUploadError) { download }

      assert_match(/deploy this version of Roe/, error.message)
    end

    private

    def start_server!
      @port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
      @server = WEBrick::HTTPServer.new(BindAddress: "127.0.0.1", Port: @port,
                                        Logger: WEBrick::Log.new(File::NULL), AccessLog: [])
      @server.mount_proc("/api/site_sync/download_info") { |req, res| answer_info(req, res) }
      @server.mount_proc("/api/site_sync/download_chunk") { |req, res| answer_chunk(req, res) }
      @thread = Thread.new { @server.start }
      sleep 0.05 until @server.status == :Running
    end

    def answer_info(req, res)
      @requests << { path: "info" }
      if @no_endpoint
        res.status = 404
        res["Content-Type"] = "text/html"
        res.body = "<html>Not Found</html>"
        return
      end
      res["Content-Type"] = "application/json"
      res.body = { path: "media/video/clip.mov", size: @data.bytesize, mtime: @mtime,
                   sha256: Digest::SHA256.hexdigest(@data) }.to_json
    end

    def answer_chunk(req, res)
      body = JSON.parse(req.body)
      offset = body["offset"].to_i
      @requests << { path: "chunk", offset: offset }
      if offset == @fail_at_offset
        res.status = 503
        res.body = "busy"
        return
      end
      bytes = @data.byteslice(offset, body["length"].to_i)
      bytes = bytes.reverse if @corrupt && offset.zero?
      res["Content-Type"] = "application/octet-stream"
      res.body = bytes
    end

    def stub_const(mod, name, value)
      old = mod.const_get(name)
      mod.send(:remove_const, name)
      mod.const_set(name, value)
      @restore_const = -> { mod.send(:remove_const, name); mod.const_set(name, old) }
    end
  end
end
