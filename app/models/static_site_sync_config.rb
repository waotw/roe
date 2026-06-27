class StaticSiteSyncConfig < ApplicationRecord
  # Three deploy targets, three different shapes:
  #   sftp / ftps — server-credential push (host/user/port/path/auth)
  #   zip         — generate a downloadable archive (no network, no creds)
  enum :protocol, { sftp: 0, ftps: 1, zip: 2 }, prefix: true
  enum :auth_mode, { password: 0, ssh_key: 1 }, prefix: true

  encrypts :password
  encrypts :ssh_private_key

  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }, allow_nil: true

  def self.current
    first_or_create!
  end

  # "Ready to use" varies by protocol — ZIP needs nothing; SFTP/FTPS
  # need full network credentials. The UI gates the push/test buttons
  # behind this so a half-filled form can't fire off a request.
  def configured?
    case protocol
    when "zip"
      true
    else
      host.present? && username.present? && remote_path.present? && credentials_present?
    end
  end

  def credentials_present?
    auth_mode_password? ? password.present? : ssh_private_key.present?
  end

  def verified?
    last_verified_at.present? && last_verification_error.blank?
  end

  # ZIP has no peer to summarise; SFTP/FTPS get the standard
  # user@host:port:path one-liner.
  def connection_summary
    return "Generates a downloadable archive (no remote host)" if protocol_zip?
    return nil unless host.present?
    "#{username}@#{host}:#{port || default_port}#{remote_path}"
  end

  def default_port
    protocol_ftps? ? 21 : 22
  end

  # SFTP/FTPS run async via StaticSiteSyncPushJob; ZIP is a synchronous
  # download. Lets the UI choose the right button/action without
  # littering the views with protocol checks.
  def push_async?
    protocol_sftp? || protocol_ftps?
  end
end
