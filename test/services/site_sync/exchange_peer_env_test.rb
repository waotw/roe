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

    test "local_state advertises this side's folder name, deploy target, subdir" do
      state = SiteSync::Exchange.local_state
      assert_equal File.basename(RoeSitePaths::ROE_ROOT), state[:env_info][:folder_name]
      assert state[:env_info].key?(:deploy_target)
      assert state[:env_info].key?(:rails_subdir)
    end

    # The fact that the live site encrypts its DB backups travels over the
    # handshake so local can show the live state — its own passphrase is
    # always empty. Only "on"/"off" travels, never the passphrase.
    test "local_state advertises whether a backup passphrase is set, never the passphrase" do
      assert_equal "off", SiteSync::Exchange.local_state[:env_info][:backup_encryption]

      SyncConfig.current.update!(backup_passphrase: "correct horse battery staple")
      info = SiteSync::Exchange.local_state[:env_info]
      assert_equal "on", info[:backup_encryption]
      assert_not_includes info.values.map(&:to_s), "correct horse battery staple"
    end

    test "peer_backup_encryption is nil until told, then true or false, and off can overwrite on" do
      c = SyncConfig.current
      assert_nil c.peer_backup_encryption

      c.merge_peer_env!("backup_encryption" => "on")
      assert_equal true, c.reload.peer_backup_encryption

      c.merge_peer_env!("backup_encryption" => "off")
      assert_equal false, c.reload.peer_backup_encryption
    end

    test "handle_inbound persists the peer's env_info as plaintext" do
      SiteSync::Exchange.handle_inbound(
        "fingerprint" => "abc",
        "env_info"    => { "folder_name" => "my-roe", "deploy_target" => "kamal", "rails_subdir" => "current" }
      )

      cfg = SyncConfig.current
      assert_equal "my-roe",  cfg.peer_folder_name
      assert_equal "kamal",   cfg.peer_deploy_target
      assert_equal "current", cfg.peer_rails_subdir
      # Plaintext: the value is readable straight from the column.
      assert_includes cfg.peer_env.to_s, "my-roe"
    end
  end
end
