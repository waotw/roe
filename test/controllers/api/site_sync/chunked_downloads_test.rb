require "test_helper"
require "fileutils"
require "digest"

module Api
  module SiteSync
    # Large files over HTTP Site Sync, live → this machine, in pieces
    # (ChunkedDownloadsController). The single-request download built a 1.2 GB
    # tar in the live server's memory and failed; these lock down the sending
    # side: the file's details, exact byte ranges, and the same path safety
    # as a normal download.
    class ChunkedDownloadsTest < ActionDispatch::IntegrationTest
      SITE = RoeSitePaths::SITE_PATH
      REL  = "media/video/zz-chunked-download.mov"

      setup do
        SyncConfig.current.update!(token: SecureRandom.hex(32))
        @token = SyncConfig.current.token
        @data = Random.bytes(10_000)
        @full = File.join(SITE, REL)
        FileUtils.mkdir_p(File.dirname(@full))
        File.binwrite(@full, @data)
        File.utime(Time.at(1_700_000_000), Time.at(1_700_000_000), @full)
      end

      teardown { FileUtils.rm_f(@full) }

      def auth = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }

      def info(path)
        post "/api/site_sync/download_info", params: { path: path }.to_json, headers: auth
      end

      def chunk(path, offset, length)
        post "/api/site_sync/download_chunk", params: { path: path, offset: offset, length: length }.to_json, headers: auth
      end

      test "info gives the size, modified time and checksum" do
        info(REL)

        assert_response :success
        body = JSON.parse(response.body)
        assert_equal 10_000, body["size"]
        assert_equal 1_700_000_000, body["mtime"]
        assert_equal Digest::SHA256.hexdigest(@data), body["sha256"]
      end

      test "pieces are exact byte ranges, and the last one is short" do
        chunk(REL, 0, 4000)
        assert_equal @data[0, 4000], response.body.b

        chunk(REL, 8000, 4000)
        assert_equal @data[8000..], response.body.b
        assert_equal "10000", response.headers["X-File-Size"]
      end

      test "an offset past the end is refused" do
        chunk(REL, 10_001, 10)
        assert_response :range_not_satisfiable
      end

      test "a piece bigger than the limit is refused" do
        chunk(REL, 0, ChunkedDownloadsController::MAX_CHUNK_BYTES + 1)
        assert_response :bad_request
      end

      test "paths outside the site, or excluded from sync, are refused" do
        [ "../config/master.key", "/etc/passwd", "system/secrets/master.key", ".sync-state.json" ].each do |path|
          info(path)
          assert_includes [ 404, 422 ], response.status, "#{path} should be refused"
          assert_no_match(/sha256/, response.body)
        end
      end

      test "a missing file says so" do
        info("media/video/not-here.mov")
        assert_response :not_found
      end

      test "needs the sync token" do
        post "/api/site_sync/download_info", params: { path: REL }.to_json,
             headers: { "Content-Type" => "application/json" }
        assert_response :unauthorized
      end
    end
  end
end
