require "test_helper"

module Api
  module SiteSync
    # After a REWIND the other side asks live to put its record of the
    # rewound files back too (Exchange.rewind_peer_ledger!), so live's own
    # report says the same side has the change as this computer's does.
    class RewindLedgerTest < ActionDispatch::IntegrationTest
      setup do
        SyncConfig.current.update!(token: SecureRandom.hex(32))
        @token = SyncConfig.current.token
        @written = nil
        ::SiteSync::Ledger.stubs(:recorded).returns(
          { "files" => { "posts/a.md" => { "size" => 9, "mtime" => 200 }, "posts/b.md" => { "size" => 5, "mtime" => 100 },
                         "posts/keep.md" => { "size" => 1, "mtime" => 1 } } }
        )
        ::SiteSync::Ledger.stubs(:write_manifest!).with { |files| @written = files }
      end

      def rewind(files, token: @token)
        post "/api/site_sync/rewind_ledger", params: { files: files }.to_json,
             headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
      end

      test "sets the given entries, removes nulls and leaves every other path alone" do
        rewind({ "posts/a.md" => { "size" => 4, "mtime" => 100 }, "posts/b.md" => nil, "posts/new.md" => { "size" => 2, "mtime" => 50 } })

        assert_response :success
        assert_equal({ "size" => 4, "mtime" => 100 }, @written["posts/a.md"])
        assert_not @written.key?("posts/b.md")
        assert_equal({ "size" => 2, "mtime" => 50 }, @written["posts/new.md"])
        assert_equal({ "size" => 1, "mtime" => 1 }, @written["posts/keep.md"])
      end

      test "refuses a path outside site/ and writes nothing" do
        rewind({ "../config/master.key" => { "size" => 1, "mtime" => 1 } })

        assert_response :bad_request
        assert_nil @written
      end

      test "needs the sync token" do
        rewind({ "posts/a.md" => nil }, token: "wrong")

        assert_response :unauthorized
        assert_nil @written
      end
    end
  end
end
