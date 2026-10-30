require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

module Api
  module SiteSync
    # Large files over HTTP Site Sync arrive in pieces and are joined back
    # together (ChunkedUploadsController). A single request for a 334 MB
    # video rendition died on the way to the live site; these lock down the
    # receiving side: pieces in order, resuming, the checksum gate, and the
    # same path safety as a normal upload.
    class ChunkedUploadsTest < ActionDispatch::IntegrationTest
      SITE = RoeSitePaths::SITE_PATH

      setup do
        # A known token for this test. The stored one is encrypted with the
        # install's key, which other tests can swap — so reading it back can
        # come up empty depending on test order.
        SyncConfig.current.update!(token: SecureRandom.hex(32))
        @token = SyncConfig.current.token
        @made = []
      end

      teardown do
        @made.each { |p| FileUtils.rm_rf(p) }
        FileUtils.rm_rf(File.join(SITE, ".sync-uploads"))
      end

      def auth = { "Authorization" => "Bearer #{@token}" }
      def id_for(data) = Digest::SHA256.hexdigest(data)[0, 32]

      def send_chunk(id, offset, size, bytes)
        post "/api/site_sync/upload_chunk?#{URI.encode_www_form(upload_id: id, offset: offset, size: size)}",
             params: bytes, headers: auth.merge("Content-Type" => "application/octet-stream")
        JSON.parse(response.body)
      end

      def send_finish(id, path, data, mtime: 1_700_000_000)
        post "/api/site_sync/upload_finish",
             params: { upload_id: id, path: path, size: data.bytesize, sha256: Digest::SHA256.hexdigest(data), mtime: mtime }.to_json,
             headers: auth.merge("Content-Type" => "application/json")
        JSON.parse(response.body)
      end

      test "pieces sent in order are joined into the file, with its mtime" do
        data = Random.bytes(10_000)
        id = id_for(data)
        rel = "media/video/variants/chunked-720p.mp4"
        @made << File.join(SITE, rel)

        assert_equal 4000, send_chunk(id, 0, data.bytesize, data[0, 4000])["received"]
        assert_equal 8000, send_chunk(id, 4000, data.bytesize, data[4000, 4000])["received"]
        assert_equal 10_000, send_chunk(id, 8000, data.bytesize, data[8000..])["received"]

        result = send_finish(id, rel, data)
        assert_response :success
        assert result["ok"]
        assert_equal data, File.binread(File.join(SITE, rel))
        assert_equal 1_700_000_000, File.mtime(File.join(SITE, rel)).to_i
        assert_not File.exist?(File.join(SITE, ".sync-uploads", "#{id}.part")), "the piece file is moved, not copied"
      end

      test "a piece at the wrong offset says how much has arrived, so the sender resumes" do
        data = Random.bytes(6000)
        id = id_for(data)
        send_chunk(id, 0, data.bytesize, data[0, 3000])

        result = send_chunk(id, 0, data.bytesize, data[0, 3000]) # a retry of the first piece
        assert_response :conflict
        assert_equal 3000, result["received"]
        assert_equal 3000, File.size(File.join(SITE, ".sync-uploads", "#{id}.part")), "nothing appended twice"
      end

      test "a file that doesn't match its checksum is thrown away, not put in place" do
        data = Random.bytes(2000)
        id = id_for(data)
        rel = "media/video/variants/bad-720p.mp4"
        send_chunk(id, 0, data.bytesize, data.reverse) # wrong bytes, right length

        result = send_finish(id, rel, data)
        assert_response :unprocessable_entity
        assert_match(/checksum/, result["error"])
        assert_not File.exist?(File.join(SITE, rel))
        assert_not File.exist?(File.join(SITE, ".sync-uploads", "#{id}.part"))
      end

      test "an incomplete file can't be finished" do
        data = Random.bytes(4000)
        id = id_for(data)
        send_chunk(id, 0, data.bytesize, data[0, 1000])

        send_finish(id, "media/video/variants/half-720p.mp4", data)
        assert_response :conflict
      end

      test "the same path safety as a normal upload: no escaping /site, no secrets" do
        data = "x" * 100
        id = id_for(data)
        send_chunk(id, 0, data.bytesize, data)

        send_finish(id, "../escape.mp4", data)
        assert_response :unprocessable_entity
        assert_not File.exist?(File.expand_path("../escape.mp4", SITE))

        secrets = File.join(SITE, "system/secrets/master.key")
        before = File.exist?(secrets) ? File.binread(secrets) : nil
        send_finish(id, "system/secrets/master.key", data)
        assert_response :unprocessable_entity
        assert(before == (File.exist?(secrets) ? File.binread(secrets) : nil), "secrets untouched")
      end

      test "pieces in progress never appear in /site's manifest" do
        data = "y" * 500
        send_chunk(id_for(data), 0, data.bytesize, data[0, 100])

        assert ::SiteSync::Ledger.current.keys.none? { |k| k.start_with?(".sync-uploads") }
      end

      test "needs the sync token" do
        post "/api/site_sync/upload_chunk?upload_id=#{'a' * 32}&offset=0&size=1", params: "x"
        assert_response :unauthorized
      end
    end
  end
end
