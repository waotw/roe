module ManagedTools
  # Detects the host OS and its package manager, and builds the correct
  # "install this package" command for that environment.
  #
  # The package-manager matrix here deliberately mirrors roe.sh's
  # build-tools step (apt/dnf/pacman/zypper/apk + Homebrew) so a user sees
  # the SAME install command whether it comes from the shell installer or
  # from this admin UI. The two are different languages (bash vs Ruby), so
  # this is shared convention, not shared code — keep them in lockstep.
  class Platform
    attr_reader :os, :package_manager

    def initialize(os:, package_manager:)
      @os = os
      @package_manager = package_manager
    end

    # Detected fresh each call — detection is a cheap PATH scan, and a
    # user who just installed a package manager should see it immediately
    # on re-check without a server restart.
    def self.current
      detect
    end

    def self.detect
      os = detect_os
      new(os: os, package_manager: detect_package_manager(os))
    end

    def macos? = os == :macos
    def linux? = os == :linux

    # Most Linux package managers need root; Homebrew does not.
    def needs_sudo?
      package_manager.present? && package_manager != :brew
    end

    # Build the full shell command to install the given package name(s).
    # Returns nil when no package manager was identified, so the caller
    # can fall back to generic guidance instead of a wrong command.
    def install_command(packages)
      pkgs = Array(packages).reject { |p| p.to_s.strip.empty? }.join(" ")
      return nil if pkgs.empty?

      case package_manager
      when :brew   then "brew install #{pkgs}"
      when :apt    then "sudo apt-get update && sudo apt-get install -y #{pkgs}"
      when :dnf    then "sudo dnf install -y #{pkgs}"
      when :yum    then "sudo yum install -y #{pkgs}"
      when :pacman then "sudo pacman -S --needed --noconfirm #{pkgs}"
      when :zypper then "sudo zypper install -y #{pkgs}"
      when :apk    then "sudo apk add #{pkgs}"
      end
    end

    # Human label, e.g. "macOS (Homebrew)" or "Linux (apt)".
    def label
      osname =
        case os
        when :macos then "macOS"
        when :linux then "Linux"
        else "your system"
        end
      manager = package_manager == :brew ? "Homebrew" : package_manager
      manager ? "#{osname} (#{manager})" : osname
    end

    def self.detect_os
      case RbConfig::CONFIG["host_os"]
      when /darwin/i then :macos
      when /linux/i  then :linux
      else :unknown
      end
    end

    # macOS resolves to Homebrew (or nil); Linux picks the first recognised
    # manager on PATH, in rough order of prevalence.
    def self.detect_package_manager(os)
      return command_available?("brew") ? :brew : nil if os == :macos

      %w[apt-get dnf yum pacman zypper apk].each do |cmd|
        return cmd == "apt-get" ? :apt : cmd.to_sym if command_available?(cmd)
      end
      nil
    end

    # Is an executable named `cmd` on PATH? A pure PATH scan (no subprocess),
    # plus the standard Homebrew bin dirs which a web-server PATH can miss
    # depending on how the server was launched.
    def self.command_available?(cmd)
      dirs = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
      dirs += ["/opt/homebrew/bin", "/usr/local/bin"] if cmd == "brew"
      dirs.any? { |dir| !dir.to_s.empty? && File.executable?(File.join(dir, cmd)) }
    end
  end
end
