require "test_helper"
require "tmpdir"
require "fileutils"
require "securerandom"

module RoeSecrets
  class BootstrapTest < ActiveSupport::TestCase
    def setup
      @dir = Dir.mktmpdir("roe-secrets-boot")
      @mk  = File.join(@dir, "master.key")
      @cr  = File.join(@dir, "credentials.yml.enc")
    end

    def teardown
      FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
    end

    def enc
      ActiveSupport::EncryptedConfiguration.new(
        config_path: @cr, key_path: @mk, env_key: "RAILS_MASTER_KEY", raise_if_missing_key: false
      )
    end

    def seed_credentials!(hash)
      File.write(@mk, SecureRandom.hex(16))
      File.chmod(0o600, @mk)
      enc.write(hash.to_yaml)
    end

    test "fresh install generates master.key + credentials with secret_key_base and AR keys" do
      assert_equal :seeded, Bootstrap.run!(secrets_dir: @dir)
      assert File.exist?(@mk)
      cfg = enc.config
      assert cfg[:secret_key_base].present?
      assert cfg.dig(:active_record_encryption, :primary_key).present?
    end

    test "adds secret_key_base to a readable credentials file, preserving AR keys" do
      seed_credentials!(
        "active_record_encryption" => {
          "primary_key" => "a" * 32, "deterministic_key" => "b" * 32, "key_derivation_salt" => "c" * 32
        }
      )

      assert_equal :seeded, Bootstrap.run!(secrets_dir: @dir)
      cfg = enc.config
      assert cfg[:secret_key_base].present?, "secret_key_base seeded"
      assert_equal "a" * 32, cfg.dig(:active_record_encryption, :primary_key), "AR keys preserved"
    end

    # The upgrade incident this heal addresses: an install whose credentials
    # predate AR encryption (secret_key_base present, AR keys absent) with an
    # EXISTING master.key. The old bootstrap only seeded AR keys alongside a
    # freshly generated master.key, so these installs never healed and the first
    # `encrypts` save crashed with a missing-primary_key error. They self-heal now.
    test "seeds AR encryption keys into a readable credentials file that lacks them" do
      seed_credentials!("secret_key_base" => "s" * 128)

      assert_equal :seeded, Bootstrap.run!(secrets_dir: @dir)
      cfg = enc.config
      assert_equal "s" * 128, cfg[:secret_key_base], "existing secret_key_base preserved"
      assert cfg.dig(:active_record_encryption, :primary_key).present?,         "AR primary_key seeded"
      assert cfg.dig(:active_record_encryption, :deterministic_key).present?,   "AR deterministic_key seeded"
      assert cfg.dig(:active_record_encryption, :key_derivation_salt).present?, "AR salt seeded"
    end

    # The incident: a restore left an empty master.key next to real credentials,
    # and the old inline bootstrap rewrote credentials — destroying the AR keys.
    test "REFUSES to overwrite credentials it cannot decrypt" do
      seed_credentials!(
        "secret_key_base" => "s" * 128,
        "active_record_encryption" => {
          "primary_key" => "p" * 32, "deterministic_key" => "d" * 32, "key_derivation_salt" => "k" * 32
        }
      )
      before = File.binread(@cr)

      # master.key is now empty (as the bad restore installed) — can't decrypt.
      File.write(@mk, "")

      assert_equal :unreadable, Bootstrap.run!(secrets_dir: @dir)
      assert_equal before, File.binread(@cr), "credentials.yml.enc must be left byte-for-byte untouched"
    end

    test "noop when everything is already present and readable" do
      seed_credentials!(
        "secret_key_base" => "s" * 128,
        "active_record_encryption" => {
          "primary_key" => "p" * 32, "deterministic_key" => "d" * 32, "key_derivation_salt" => "k" * 32
        }
      )
      before = File.binread(@cr)

      assert_equal :noop, Bootstrap.run!(secrets_dir: @dir)
      assert_equal before, File.binread(@cr), "no write when nothing is missing"
    end
  end
end
