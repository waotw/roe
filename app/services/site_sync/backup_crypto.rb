require "openssl"
require "securerandom"
require "fileutils"

module SiteSync
  # Passphrase-based encryption for the one file Site Sync deliberately
  # never carries over the wire: the SQLite database. A full-site backup
  # bundles everything as-is EXCEPT the DB, which is replaced by a
  # <name>.enc blob produced here.
  #
  # The point is to protect member/store PII in *copies that leave the
  # box* (a pulled backup on a laptop, a stolen snapshot) without touching
  # the live server: the running DB stays plaintext so background jobs,
  # public member auth, and webhooks keep working with no human present.
  # Decryption happens locally, where the admin has the passphrase — the
  # passphrase never travels and the live server never needs it.
  #
  # Blob layout (all binary, concatenated):
  #   MAGIC(6) | salt(16) | iv(12) | ciphertext(N) | tag(16)
  #
  # AES-256-GCM with a key derived from the passphrase via PBKDF2-HMAC-
  # SHA256. The 6-byte MAGIC doubles as a version marker and is
  # authenticated as additional data, so a truncated or edited header
  # fails the tag check rather than silently mis-decrypting. The tag
  # trails the ciphertext so encryption can stream the source in chunks
  # (large DBs never sit in memory whole); on decrypt the file is
  # seekable, so the trailing tag is read first.
  class BackupCrypto
    class Error < StandardError; end
    class DecryptError < Error; end   # wrong passphrase or corrupt/tampered blob
    class FormatError  < Error; end   # not a Roe backup blob at all

    MAGIC          = "ROEBK1".b.freeze # Roe BacKup, format v1
    SALT_LEN       = 16
    IV_LEN         = 12                # GCM standard nonce length
    TAG_LEN        = 16
    KEY_LEN        = 32                # AES-256
    KDF_ITERATIONS = 210_000          # PBKDF2-HMAC-SHA256, OWASP 2023 floor
    CIPHER         = "aes-256-gcm"
    CHUNK          = 64 * 1024

    HEADER_LEN = MAGIC.bytesize + SALT_LEN + IV_LEN

    class << self
      # Encrypt source_path -> dest_path. Writes to a temp file and renames,
      # so a crash mid-write never leaves a truncated .enc in place. Returns
      # dest_path.
      def encrypt_file(source_path, dest_path, passphrase)
        raise Error, "passphrase is blank"          if passphrase.to_s.empty?
        raise Error, "source not found: #{source_path}" unless File.file?(source_path)

        salt   = SecureRandom.random_bytes(SALT_LEN)
        iv     = SecureRandom.random_bytes(IV_LEN)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key       = derive_key(passphrase, salt)
        cipher.iv        = iv
        cipher.auth_data = MAGIC

        write_atomically(dest_path) do |out|
          out.write(MAGIC)
          out.write(salt)
          out.write(iv)
          File.open(source_path, "rb") do |src|
            while (chunk = src.read(CHUNK))
              out.write(cipher.update(chunk))
            end
          end
          out.write(cipher.final)
          out.write(cipher.auth_tag(TAG_LEN)) # trailing 16-byte tag
        end

        dest_path
      end

      # Decrypt source_path (an .enc blob) -> dest_path. Raises DecryptError
      # on a wrong passphrase or a corrupt/tampered file, and never leaves a
      # partial plaintext in place (decrypts to a temp file, renames on
      # success). Returns dest_path.
      def decrypt_file(source_path, dest_path, passphrase)
        write_atomically(dest_path) do |out|
          stream_decrypt(source_path, passphrase) { |chunk| out.write(chunk) }
        end
        dest_path
      end

      # True if the blob decrypts cleanly with this passphrase, without ever
      # writing plaintext to disk (streams straight to a discard sink). Use
      # to confirm a freshly written backup is openable, or to validate a
      # passphrase before a restore.
      def verify(source_path, passphrase)
        stream_decrypt(source_path, passphrase) { |_chunk| } # discard
        true
      rescue Error
        false
      end

      # Cheap structural check (magic + minimum length) without a passphrase.
      # Distinguishes "this isn't a Roe backup blob" from "wrong passphrase".
      def blob?(source_path)
        return false unless File.file?(source_path)
        return false if File.size(source_path) < HEADER_LEN + TAG_LEN
        File.open(source_path, "rb") { |f| f.read(MAGIC.bytesize) == MAGIC }
      rescue SystemCallError
        false
      end

      private

      def stream_decrypt(source_path, passphrase)
        raise Error, "passphrase is blank"          if passphrase.to_s.empty?
        raise Error, "source not found: #{source_path}" unless File.file?(source_path)

        size = File.size(source_path)
        raise FormatError, "file too small to be a Roe backup blob" if size < HEADER_LEN + TAG_LEN

        File.open(source_path, "rb") do |src|
          magic = src.read(MAGIC.bytesize)
          raise FormatError, "bad magic — not a Roe backup blob" unless magic == MAGIC

          salt = src.read(SALT_LEN)
          iv   = src.read(IV_LEN)
          body = src.pos                 # first ciphertext byte
          tag_pos = size - TAG_LEN

          src.seek(tag_pos)
          tag = src.read(TAG_LEN)
          src.seek(body)

          decipher = OpenSSL::Cipher.new(CIPHER).decrypt
          decipher.key       = derive_key(passphrase, salt)
          decipher.iv        = iv
          decipher.auth_data = MAGIC

          remaining = tag_pos - body
          begin
            while remaining > 0
              chunk = src.read([ CHUNK, remaining ].min)
              break if chunk.nil?
              remaining -= chunk.bytesize
              yield decipher.update(chunk)
            end
            decipher.auth_tag = tag       # must be set before final
            yield decipher.final          # raises on wrong passphrase / bad tag
          rescue OpenSSL::Cipher::CipherError
            raise DecryptError, "wrong passphrase or corrupt backup"
          end
        end
      end

      def derive_key(passphrase, salt)
        OpenSSL::KDF.pbkdf2_hmac(
          passphrase.to_s,
          salt:       salt,
          iterations: KDF_ITERATIONS,
          length:     KEY_LEN,
          hash:       "sha256"
        )
      end

      # Write to "<dest>.tmp-XXXX" then rename over dest, cleaning up the temp
      # on any failure. Keeps a crash or bad decrypt from publishing a partial
      # file where a valid one is expected.
      def write_atomically(dest_path)
        FileUtils.mkdir_p(File.dirname(dest_path))
        tmp = "#{dest_path}.tmp-#{SecureRandom.hex(6)}"
        begin
          File.open(tmp, "wb") { |out| yield out }
          FileUtils.mv(tmp, dest_path)
        ensure
          FileUtils.rm_f(tmp)
        end
      end
    end
  end
end
