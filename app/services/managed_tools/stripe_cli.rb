module ManagedTools
  # Stripe CLI — Stripe's official command-line tool. Roe uses it only for
  # LOCAL development: `stripe listen` forwards live test-mode webhook events
  # to the local server, so an owner can test the full checkout → upgrade flow
  # without a public URL or a tunnel. Not needed in production (real Stripe
  # delivers webhooks straight to the deployed site). See `roe stripe`.
  #
  # Unlike libvips this isn't a library Roe links against — it's a binary on
  # PATH that the `roe stripe` launcher shells out to. Detection is therefore a
  # PATH check, and install guidance is hand-written per platform because the
  # Stripe CLI isn't in the default Linux repos (it needs Stripe's own apt/yum
  # source added first) — a bare `apt install stripe` would just fail.
  class StripeCli < Tool
    def key      = :stripe
    def label    = "Stripe CLI"
    def summary  = "Stripe's command-line tool (local webhook testing)"
    def why      = "Roe uses the Stripe CLI to forward test-mode webhooks to your local server so you can test checkout and upgrades without a public URL. Only needed for local development."
    def docs_url = "https://stripe.com/docs/stripe-cli"
    def group    = :development

    # A binary on PATH, not a linked library — mirror Platform.command_available?
    # (pure PATH scan plus the Homebrew bin dirs a web-server PATH can miss).
    def installed?
      Platform.command_available?("stripe")
    rescue => e
      Rails.logger.debug { "[ManagedTools::StripeCli] detection error: #{e.message}" }
      false
    end

    def version
      return nil unless installed?

      out = `stripe --version 2>/dev/null`.to_s.strip
      # e.g. "stripe version 1.53.0" → "1.53.0"
      out[/\d+\.\d+\.\d+/] || (out.empty? ? nil : out)
    rescue StandardError
      nil
    end

    # Hand-written per platform: Homebrew needs Stripe's tap, and Linux needs
    # Stripe's custom repo added before `apt/yum install stripe` works — that's
    # multi-step, so we point at the docs rather than emit a command that fails.
    # No method is usable on anything we can't give a one-line, correct
    # command for, so the caller falls back to "see docs" guidance.
    def install_methods(platform = Platform.current)
      if platform.macos? && platform.package_manager == :brew
        [ InstallMethod.new(key: :package_manager, label: "Homebrew", command: "brew install stripe/stripe-cli/stripe",
                            usable: true, sudo: false, restart: false) ]
      else
        [ InstallMethod.new(key: :package_manager, label: platform.manager_label, usable: false,
                            reason: "The Stripe CLI needs Stripe's own package source added first. Follow Stripe's install guide.") ]
      end
    end
  end
end
