require "test_helper"
require "tmpdir"
require "fileutils"

module Api
  module SiteSync
    # Request specs for the two byte-transfer endpoints that back the
    # HTTP transport: POST /api/site_sync/download (packs requested files
    # into a gzip tar) and POST /api/site_sync/upload (unpacks an uploaded
    # tar into /site, restores mtimes, applies deletions). Auth + the
    # security filtering are the important behaviours to lock down.
    class ExchangeTransferTest < ActionDispatch::IntegrationTest
      SITE = RoeSitePaths::SITE_PATH

      def setup
        @token = SyncConfig.current.token
        @created = []
      end

      def teardown
        @created.each { |p| FileUtils.rm_rf(p) }
      end

      def site_write(rel, content)
        full = File.join(SITE, rel)
        FileUtils.mkdir_p(File.dirname(full))
        File.binwrite(full, content)
        @created << full
        full
      end

      def auth
        { "Authorization" => "Bearer #{@token}" }
      end

      # -------------------------------------------------------------- auth

      test "download rejects a request with no/invalid token" do
        post "/api/site_sync/download",
             params: { paths: [ "site.yml" ] }.to_json,
             headers: { "Content-Type" => "application/json" }
        assert_response :unauthorized
      end

      # ---------------------------------------------------------- download

      test "download packs requested files and filters excluded/unsafe paths" do
        site_write("posts/dl_a.md", "alpha")
        site_write("posts/dl_b.md", "beta")

        post "/api/site_sync/download",
             params: {
               paths: [
                 "posts/dl_a.md",
                 "posts/dl_b.md",
                 "system/secrets/master.key", # excluded — must not be served
                 "../etc/passwd"              # traversal — must be dropped
               ]
             }.to_json,
             headers: auth.merge("Content-Type" => "application/json")

        assert_response :success
        assert_equal "application/gzip", response.media_type

        dst = Dir.mktmpdir("dl-unpack")
        @created << dst
        written = ::SiteSync::TarArchive.unpack(response.body, dest: dst)

        assert_equal [ "posts/dl_a.md", "posts/dl_b.md" ], written
        assert_equal "alpha", File.read(File.join(dst, "posts/dl_a.md"))
        refute File.exist?(File.join(dst, "system/secrets/master.key"))
      end

      # ------------------------------------------------------------ upload

      test "upload unpacks the archive, restores mtimes, and applies deletions" do
        # Build an archive out-of-band from a temp source tree.
        src = Dir.mktmpdir("up-src")
        @created << src
        FileUtils.mkdir_p(File.join(src, "posts"))
        File.write(File.join(src, "posts/up_a.md"), "uploaded")
        archive_bytes = ::SiteSync::TarArchive.pack(root: src, paths: [ "posts/up_a.md" ])

        tar = Tempfile.create([ "upload", ".tar.gz" ])
        tar.binmode
        tar.write(archive_bytes)
        tar.rewind

        # A file that already lives in /site and should be deleted.
        gone = site_write("posts/up_delete.md", "bye")
        # Track the file the upload will create so teardown cleans it.
        @created << File.join(SITE, "posts/up_a.md")

        mtime = 1_610_000_000
        post "/api/site_sync/upload",
             params: {
               archive:  Rack::Test::UploadedFile.new(tar.path, "application/gzip"),
               manifest: { "posts/up_a.md" => { "size" => 8, "mtime" => mtime } }.to_json,
               deleted:  [ "posts/up_delete.md" ].to_json
             },
             headers: auth

        assert_response :success
        body = JSON.parse(response.body)
        assert body["ok"]
        assert_equal 1, body["written"]
        assert_equal 1, body["deleted"]

        landed = File.join(SITE, "posts/up_a.md")
        assert_equal "uploaded", File.read(landed)
        assert_equal mtime, File.stat(landed).mtime.to_i, "mtime should be restored from the manifest"
        refute File.exist?(gone), "deleted path should be removed from /site"
      ensure
        tar&.close
        File.unlink(tar.path) if tar && File.exist?(tar.path)
      end

      test "upload with a missing archive part is a bad request" do
        post "/api/site_sync/upload",
             params: { manifest: "{}", deleted: "[]" },
             headers: auth
        assert_response :bad_request
      end

      # ------------------------------------------------------- file_hashes

      test "file_hashes returns SHA256 per path and filters excluded/unsafe ones" do
        site_write("posts/fh.md", "hash me")

        post "/api/site_sync/file_hashes",
             params: { paths: [ "posts/fh.md", "system/secrets/master.key", "../etc/passwd" ] }.to_json,
             headers: auth.merge("Content-Type" => "application/json")

        assert_response :success
        hashes = JSON.parse(response.body)["hashes"]
        assert_equal Digest::SHA256.hexdigest("hash me"), hashes["posts/fh.md"]
        refute hashes.key?("system/secrets/master.key"), "must not hash an excluded secret"
        refute hashes.key?("../etc/passwd")
      end

      test "file_hashes rejects an unauthenticated request" do
        post "/api/site_sync/file_hashes",
             params: { paths: [ "site.yml" ] }.to_json,
             headers: { "Content-Type" => "application/json" }
        assert_response :unauthorized
      end
    end
  end
end
