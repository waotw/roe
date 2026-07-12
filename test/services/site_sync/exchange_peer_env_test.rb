require "test_helper"

module SiteSync
  # Chunk 1 of the restore-recovery UX: the peer's environment (folder name +
  # deploy target) travels over the sync handshake and is persisted plaintext,
  # so production can render accurate "restart on your local machine"
  # instructions even when AR encryption is broken.
  class ExchangePeerEnvTest < ActiveSupport::TestCase
    def setup
      SyncConfig.delete_all
    end

    test "SyncConfig stores + reads peer env, ignoring non-whitelisted keys" do
      c = SyncConfig.current
      c.merge_peer_env!("folder_name" => "roe-dev", "deploy_target" => "kamal", "evil" => "x")
      c.reload

      assert_equal "roe-dev", c.peer_folder_name
      assert_equal "kamal",   c.peer_deploy_target
      assert_nil c.peer_env_hash["evil"], "only whitelisted keys are stored"
    end

    test "merge_peer_env! skips the write when nothing changed" do
      c = SyncConfig.current
      c.merge_peer_env!("folder_name" => "roe")
      before = c.reload.peer_env

      c.merge_peer_env!("folder_name" => "roe") # identical
      assert_equal before, c.reload.peer_env
    end

    test "local_state advertises this side's folder name + deploy target" do
      state = SiteSync::Exchange.local_state
      assert_equal File.basename(RoeSitePaths::ROE_ROOT), state[:env_info][:folder_name]
      assert state[:env_info].key?(:deploy_target)
    end

    test "handle_inbound persists the peer's env_info as plaintext" do
      SiteSync::Exchange.handle_inbound(
        "fingerprint" => "abc",
        "env_info"    => { "folder_name" => "my-roe", "deploy_target" => "kamal" }
      )

      cfg = SyncConfig.current
      assert_equal "my-roe", cfg.peer_folder_name
      assert_equal "kamal",  cfg.peer_deploy_target
      # Plaintext: the value is readable straight from the column.
      assert_includes cfg.peer_env.to_s, "my-roe"
    end
  end
end
