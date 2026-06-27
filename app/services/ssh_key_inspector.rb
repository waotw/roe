require "open3"

# Scans ~/.ssh/ for public keys and returns a lightweight inventory the
# admin UI can render. Read-only — never touches files, never prompts.
#
# Each entry surfaces:
#   filename    "id_ed25519.pub"
#   path        "/Users/you/.ssh/id_ed25519.pub"
#   key_type    "ssh-ed25519" / "ssh-rsa" / etc.
#   comment     trailing text from the pub-key line (often the email)
#   fingerprint SHA256 fingerprint via `ssh-keygen -lf` (nil if the
#               command failed — keys still listed, just without the
#               fingerprint hint)
#   public_key  the raw single-line pub-key string (for the copy button)
class SshKeyInspector
  Key = Struct.new(:filename, :path, :key_type, :comment, :fingerprint, :public_key, keyword_init: true)

  def self.list
    new.list
  end

  def initialize(ssh_dir: File.join(Dir.home, ".ssh"))
    @ssh_dir = ssh_dir
  end

  # Walk ~/.ssh, surface every *.pub the inspector can parse. Returns
  # an empty array if the directory's missing — the panel just hides
  # itself in that case.
  def list
    return [] unless File.directory?(@ssh_dir)

    Dir.glob(File.join(@ssh_dir, "*.pub")).sort.filter_map do |path|
      parse(path)
    rescue StandardError
      # One malformed file shouldn't blank the whole list — skip it.
      nil
    end
  end

  private

  def parse(path)
    contents = File.read(path).strip
    return nil if contents.empty?

    # Pub-key file format: "<type> <base64-blob> [comment with spaces]"
    type, blob, *comment_parts = contents.split(/\s+/, 3)
    return nil unless type && blob

    Key.new(
      filename:    File.basename(path),
      path:        path,
      key_type:    type,
      comment:     comment_parts.join(" ").presence,
      fingerprint: fingerprint_for(path),
      public_key:  contents
    )
  end

  # `ssh-keygen -lf <path>` prints "<bits> SHA256:<digest> <comment> (<type>)".
  # We just want the SHA256 line. Capture stderr too so we can silently
  # bail when the file isn't actually a key.
  def fingerprint_for(path)
    out, status = Open3.capture2e("ssh-keygen", "-lf", path)
    return nil unless status.success?

    match = out.match(/SHA256:\S+/)
    match && match[0]
  end
end
