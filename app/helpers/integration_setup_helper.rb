module IntegrationSetupHelper
  # Integrations whose SETUP has no real local value: the live half can't
  # complete without a deployed public URL, and it has to be redone in
  # production anyway (see the payments/newsletters integration notes). So in
  # development we hide the local setup surface and instead point the operator
  # at their live site. Snipcart is deliberately absent — its snippet runs live
  # locally and needs no production setup step, so local setup IS the setup.
  HIDEABLE_LOCAL_SETUP = %w[payments].freeze # newsletters can be added here later

  # Hide the local setup UI for this integration? Only ever hides outside
  # production, only for the integrations above, and stays reversible: set
  #   development:
  #     show_local_integration_setup: true
  # in development.yml to bring the full local UI back.
  def local_integration_setup_hidden?(config_type)
    return false unless Rails.env.development?
    return false unless HIDEABLE_LOCAL_SETUP.include?(config_type.to_s)
    return false if integration_ui_production? # previewing prod → show the real UI
    !local_integration_setup_override?
  end

  # The escape hatch. Truthy dev flag re-enables the local setup UI.
  def local_integration_setup_override?
    ActiveModel::Type::Boolean.new.cast(SiteConfig.development("show_local_integration_setup"))
  rescue StandardError
    false
  end

  # Whether the integration pages should RENDER as if in production — the real
  # thing in production, or a dev-only preview when you append ?preview=production
  # to the URL. Lets you eyeball the production copy/UI (two tabs, live states)
  # locally without booting RAILS_ENV=production. Never true outside dev except
  # in actual production, so it can't leak a live-keys form onto a real dev box
  # (the controller still refuses to persist live keys unless Rails.env is
  # genuinely production).
  def integration_ui_production?
    Rails.env.production? || (Rails.env.development? && params[:preview] == "production")
  end

  # Best-effort URL to the operator's live admin, for the "set this up on your
  # live site" copy. Nil when we don't know the live URL yet (not deployed /
  # no Site URL set), so the copy can fall back to "deploy first".
  def live_admin_url
    base = SiteConfig.site_url.to_s.strip
    return nil if base.blank?

    "#{base.chomp('/')}/admin"
  rescue StandardError
    nil
  end

  # Has this install actually completed a deploy? Authoritative:
  # .last_deploy.yml is written ONLY when a deploy finishes successfully
  # (PerformDeployJob), so this means "we shipped", not merely "a Site URL was
  # typed into site.yml". Used to decide whether the live-site pointer can send
  # them to a real admin or should tell them to deploy first.
  def site_deployed?
    file = PerformDeployJob::LAST_DEPLOY_FILE
    return false unless File.exist?(file)

    data = YAML.safe_load_file(file, permitted_classes: [ Symbol, Time, Date ])
    return false unless data.is_a?(Hash)

    (data["completed_at"] || data[:completed_at]).present?
  rescue StandardError
    false
  end
end
