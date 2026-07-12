require "rubygems/package"
require "zlib"
require "tmpdir"
require "fileutils"

module SiteSync
  # A full-DR backup of the live database: the SQLite DB plus the crypto
  # material needed to actually use it — master.key and credentials.yml.enc,
  # which together hold the Active Record Encryption keys that protect the
  # DB's integration secrets (Stripe/Postmark tokens etc.). All packed into
  # one gzip tar and encrypted with the backup passphrase (via BackupCrypto),
  # so a single .enc + passphrase can rebuild live — and the keys are never
  # stored in plaintext.
  #
  # unpack auto-detects format: a new bundle is a gzip tar; a legacy backup
  # is a bare encrypted SQLite file. Both restore.
  class BackupBundle
    class Error < StandardError; end

    DB_ENTRY          = "database.sqlite3".freeze
    MASTER_KEY_ENTRY  = "master.key".freeze
    CREDENTIALS_ENTRY = "credentials.yml.enc".freeze

    GZIP_MAGIC = "\x1f\x8b".b.freeze

    class << self
      # Pack db + secrets into a gzip tar and encrypt it to dest_enc. Secrets
      # (master.key/credentials.yml.enc under secrets_dir) are included when
      # present. Returns dest_enc.
      def pack(db_path:, secrets_dir:, dest_enc:, passphrase:)
        raise Error, "database not found: #{db_path}" unless File.file?(db_path)

        Dir.mktmpdir("roe-bundle") do |tmp|
          tar_path = File.join(tmp, "bundle.tar.gz")
          write_tar(tar_path, db_path, secrets_dir)
          BackupCrypto.encrypt_file(tar_path, dest_enc, passphrase)
        end
        dest_enc
      end

      # Decrypt + unpack enc_path into dest_dir. Returns a hash of what was
      # written, e.g. { db:, master_key:, credentials: } (only the keys that
      # were present). Raises BackupCrypto::DecryptError on a wrong passphrase.
      def unpack(enc_path:, dest_dir:, passphrase:)
        FileUtils.mkdir_p(dest_dir)

        Dir.mktmpdir("roe-unbundle") do |tmp|
          plain = File.join(tmp, "payload")
          BackupCrypto.decrypt_file(enc_path, plain, passphrase)

          if gzip?(plain)
            extract_tar(plain, dest_dir)
          else
            # Legacy bare-SQLite backup: the decrypted payload IS the database.
            db_out = File.join(dest_dir, DB_ENTRY)
            FileUtils.mv(plain, db_out)
            { db: db_out }
          end
        end
      end

      private

      def write_tar(tar_path, db_path, secrets_dir)
        File.open(tar_path, "wb") do |file|
          Zlib::GzipWriter.wrap(file) do |gz|
            Gem::Package::TarWriter.new(gz) do |tar|
              add_file(tar, DB_ENTRY, db_path)
              {
                MASTER_KEY_ENTRY  => "master.key",
                CREDENTIALS_ENTRY => "credentials.yml.enc"
              }.each do |entry, fname|
                src = File.join(secrets_dir.to_s, fname)
                add_file(tar, entry, src) if File.file?(src)
              end
            end
          end
        end
      end

      def add_file(tar, name, path)
        stat = File.stat(path)
        tar.add_file_simple(name, stat.mode & 0o777, stat.size) do |out|
          File.open(path, "rb") { |f| IO.copy_stream(f, out) }
        end
      end

      def extract_tar(tar_gz_path, dest_dir)
        written = {}
        File.open(tar_gz_path, "rb") do |file|
          Zlib::GzipReader.wrap(file) do |gz|
            Gem::Package::TarReader.new(gz) do |tar|
              tar.each do |entry|
                next unless entry.file?
                # Flat names only — defend against any path in the archive.
                name = File.basename(entry.full_name)
                key = { DB_ENTRY => :db, MASTER_KEY_ENTRY => :master_key,
                        CREDENTIALS_ENTRY => :credentials }[name]
                next unless key

                out = File.join(dest_dir, name)
                File.open(out, "wb") { |o| IO.copy_stream(entry, o) }
                written[key] = out
              end
            end
          end
        end
        written
      end

      def gzip?(path)
        File.open(path, "rb") { |f| f.read(2) } == GZIP_MAGIC
      rescue SystemCallError
        false
      end
    end
  end
end
