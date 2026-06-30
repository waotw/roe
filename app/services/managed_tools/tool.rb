module ManagedTools
  # Base class for an optional external tool/library that Roe can use but
  # doesn't bundle (libvips, ImageMagick, ffmpeg, …). Subclass it, fill in
  # the metadata + detection + per-manager package names, and list the
  # subclass in ManagedTools.all.
  #
  # Everything that cares about a tool — the admin Dependencies page, a
  # feature that degrades without it — then asks the same two questions
  # uniformly: is it installed, and if not, how does THIS user install it?
  #
  # Tools are deliberately stateless: detection runs on every call so a
  # re-check after installing reflects reality without a server restart.
  class Tool
    # ── Metadata (override in subclasses) ──────────────────────────────
    def key      = raise(NotImplementedError, "#{self.class} must define #key") # Symbol, e.g. :libvips
    def label    = raise(NotImplementedError, "#{self.class} must define #label")
    def summary  = ""    # one line: what it is
    def why      = ""    # why Roe uses it / what's lost without it
    def optional? = true # does the app run without it?
    def docs_url = nil

    # ── Detection (override) ───────────────────────────────────────────
    # Return true when the tool is installed AND usable. Must not raise.
    def installed? = raise(NotImplementedError, "#{self.class} must define #installed?")

    # Optional version string when installed (nil if unknown/not installed).
    def version = nil

    # ── Install guidance (override #packages) ──────────────────────────
    # Map a package-manager symbol to the package name(s) it ships under,
    # e.g. { brew: "vips", apt: "libvips", dnf: "vips" }. A manager absent
    # from the map yields no command (caller shows generic guidance).
    def packages = {}

    def install_command(platform = Platform.current)
      platform.install_command(packages[platform.package_manager])
    end

    # A plain-hash status snapshot for views — re-detects every call.
    def status(platform = Platform.current)
      present = installed?
      {
        key:             key,
        label:           label,
        summary:         summary,
        why:             why,
        optional:        optional?,
        docs_url:        docs_url,
        installed:       present,
        version:         (present ? version : nil),
        install_command: install_command(platform),
        platform_label:  platform.label,
        needs_sudo:      platform.needs_sudo?,
      }
    end
  end
end
