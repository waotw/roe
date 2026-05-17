module SiteSync
  # Returns the active rsync transport class based on the deploy
  # target. SiteSyncTransferJob calls SiteSync.transport.push_local_to_live!
  # etc. — neither the job nor the admin UI cares whether the
  # underlying transport is fly-rsync or plain ssh.
  #
  # Detection precedence:
  #   1. ROE_DEPLOY_TARGET env var ("kamal" / "fly") — explicit override
  #   2. .kamal/secrets file exists → :kamal (created by `kamal init`,
  #      a strong "I'm using Kamal" signal that Rails 8's stub
  #      config/deploy.yml doesn't carry on its own)
  #   3. fly.toml exists → :fly
  #   4. Nothing detected → raise on use; SyncConfig form will show
  #      "no deploy target configured"
  def self.transport
    case deploy_target
    when :kamal then SiteSync::KamalRsync
    when :fly   then SiteSync::FlyRsync
    else
      raise "No deploy target detected. Either set ROE_DEPLOY_TARGET=kamal|fly, " \
            "create .kamal/secrets via `kamal init`, or have fly.toml in the app root."
    end
  end

  def self.deploy_target
    # 1. Explicit env var override
    return ENV['ROE_DEPLOY_TARGET'].to_sym if ENV['ROE_DEPLOY_TARGET'].present?

    # 2. Check deploy.yml target setting (most reliable - user-configured)
    if File.exist?(SiteConfig::DEPLOY_FILE)
      config = YAML.load_file(SiteConfig::DEPLOY_FILE) rescue {}
      target = config['target'].to_s.downcase
      return :kamal if target == 'kamal'
      return :fly if target == 'fly'
    end

    # 3. Fall back to file detection for legacy/auto-detection
    return :kamal if File.exist?(Rails.root.join('.kamal', 'secrets'))
    return :fly   if File.exist?(Rails.root.join('fly.toml'))
    nil
  end

  # Human-readable label for the active deploy target. Used in the
  # admin Site Sync settings panel so the user can see at a glance
  # which mode the app is operating in.
  def self.deploy_target_label
    case deploy_target
    when :kamal then "Kamal"
    when :fly   then "Fly"
    else             "Not configured"
    end
  end
end
