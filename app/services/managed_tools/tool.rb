module ManagedTools
  # Base class for an optional external tool/library that Roe can use but
  # doesn't bundle (libvips, ImageMagick, ffmpeg, …). Subclass it, fill in
  # the metadata + detection + per-manager package names, and list the
  # subclass in ManagedTools.all.
  #
  # Everything that cares about a tool — the admin Tools pages, `roe
  # install`, a feature that degrades without it — then asks the same two
  # questions uniformly: is it installed, and if not, how does THIS user
  # install it?
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

    # Which Tools page lists it: :media (Images & Video) or :development
    # (Developer Tools). See Admin::DependenciesController.
    def group = :media

    # ── Detection (override) ───────────────────────────────────────────
    # Return true when the tool is installed AND usable. Must not raise.
    def installed? = raise(NotImplementedError, "#{self.class} must define #installed?")

    # Optional version string when installed (nil if unknown/not installed).
    def version = nil

    # Optional extra line for the Dependencies page when the tool is only
    # partly there (nil when there's nothing to add).
    def note = nil

    # ── Install guidance (override #packages) ──────────────────────────
    # Map a package-manager symbol to the package name(s) it ships under,
    # e.g. { brew: "vips", apt: "libvips", dnf: "vips" }. A manager absent
    # from the map yields no command (caller shows generic guidance).
    def packages = {}

    # The Homebrew formula name, used to ask whether Homebrew has a
    # ready-made build for this macOS. Defaults to the brew package.
    def homebrew_formula = packages[:brew]

    # The single command to show when there's only room for one: the
    # recommended method's command, if it has one.
    def install_command(platform = Platform.current)
      recommended_install(platform)&.command
    end

    # ── Install methods ─────────────────────────────────────────────────
    #
    # Every way this tool could be installed here, best first, each marked
    # usable or not with the reason in plain words. `roe install` offers the
    # first usable one and moves to the next if it fails; the Tools pages
    # show the recommended one.
    #
    #   key       :package_manager, :mise, :download
    #   label     "Homebrew", "mise", "Direct download"
    #   command   shell command to run, or nil when Roe does the work itself
    #             (a download — the CLI calls `rails roe:tools:download`)
    #   usable    can it be tried on this computer?
    #   reason    why not, or a caution, in plain words
    #   detail    one line about what it gives you ("about 130 MB")
    #   sudo      will it ask for the computer's password?
    #   restart   do running sites need a restart to see it?
    InstallMethod = Struct.new(:key, :label, :command, :usable, :reason, :detail, :sudo, :restart,
                               keyword_init: true) do
      def usable? = usable
      def to_h = super.merge(usable: usable?)
    end

    # Default: the system package manager only. Tools with more ways to be
    # installed (ffmpeg) override this and add theirs.
    def install_methods(platform = Platform.current)
      [ package_manager_method(platform) ]
    end

    def recommended_install(platform = Platform.current)
      install_methods(platform).find(&:usable?)
    end

    # A plain-hash status snapshot for views — re-detects every call.
    def status(platform = Platform.current)
      present = installed?
      methods = present ? [] : install_methods(platform)
      best = methods.find(&:usable?)
      {
        key:             key,
        label:           label,
        summary:         summary,
        why:             why,
        optional:        optional?,
        docs_url:        docs_url,
        installed:       present,
        version:         (present ? version : nil),
        note:            (present ? nil : note),
        install_methods: methods.map(&:to_h),
        install_method:  best&.to_h,
        install_command: best&.command,
        platform_label:  platform.label,
        system_label:    platform.system_label,
        needs_sudo:      best ? best.sudo : platform.needs_sudo?
      }
    end

    private

    # The system package manager: Homebrew on macOS, apt/dnf/… on Linux.
    # On macOS, Homebrew is skipped when it has no ready-made build for
    # this macOS, because it would compile everything from source.
    def package_manager_method(platform)
      pkg = packages[platform.package_manager]
      command = platform.install_command(pkg)
      label = platform.manager_label
      return InstallMethod.new(key: :package_manager, label: label, usable: false,
                               reason: no_manager_reason(platform)) unless command

      if platform.package_manager == :brew && homebrew_formula && platform.homebrew_bottle?(homebrew_formula) == false
        # No ready-made build: Homebrew would compile it and its libraries.
        # Fine to offer (with a warning) when there's no other way, as for
        # libvips; skipped when the tool has better options, as ffmpeg does.
        return InstallMethod.new(
          key: :package_manager, label: label, command: command,
          usable: build_from_source_ok?,
          reason: "Homebrew no longer has ready-made builds for macOS #{platform.macos_major}, so it would build #{self.label} from source, which can take a long time.",
          sudo: false, restart: false
        )
      end

      InstallMethod.new(key: :package_manager, label: label, command: command, usable: true,
                        sudo: platform.needs_sudo?, restart: false)
    end

    # Should Homebrew still be offered when it would have to build from
    # source? Yes by default — slow beats impossible. Tools with another
    # way in (ffmpeg's download) say no, so that way is tried first.
    def build_from_source_ok? = true

    def no_manager_reason(platform)
      if platform.package_manager
        "#{platform.manager_label} doesn't have a #{label} package Roe knows about."
      elsif platform.macos?
        "Homebrew isn't installed."
      else
        "No package manager Roe recognises was found."
      end
    end
  end
end
