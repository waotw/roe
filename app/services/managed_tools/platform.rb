require "open3"

module ManagedTools
  # Detects the host OS, its version and chip, and its package manager, and
  # builds the correct "install this package" command for that environment.
  #
  # The package-manager matrix here deliberately mirrors roe.sh's
  # build-tools step (apt/dnf/pacman/zypper/apk + Homebrew) so a user sees
  # the SAME install command whether it comes from the shell installer or
  # from this admin UI. The two are different languages (bash vs Ruby), so
  # this is shared convention, not shared code — keep them in lockstep.
  class Platform
    attr_reader :os, :package_manager, :arch, :os_version

    def initialize(os:, package_manager:, arch: nil, os_version: nil)
      @os = os
      @package_manager = package_manager
      @arch = arch
      @os_version = os_version
    end

    # Detected fresh each call — detection is a cheap PATH scan, and a
    # user who just installed a package manager should see it immediately
    # on re-check without a server restart.
    def self.current
      detect
    end

    def self.detect
      os = detect_os
      new(os: os, package_manager: detect_package_manager(os),
          arch: detect_arch, os_version: detect_os_version(os))
    end

    def macos? = os == :macos
    def linux? = os == :linux

    # "14" from "14.8.5" — the number Homebrew support is decided by.
    def macos_major = macos? ? os_version.to_s.to_i : nil

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

    # "macOS 14.8.5 · Apple Silicon", "Ubuntu 24.04.1 LTS · x86_64".
    def system_label
      name = macos? ? [ "macOS", os_version ].compact.join(" ") : (os_version.presence || label)
      chip = { arm64: (macos? ? "Apple Silicon" : "arm64"), x86_64: (macos? ? "Intel" : "x86_64") }[arch]
      [ name, chip ].compact.join(" · ")
    end

    # "Homebrew", "apt", … — the name to show for a package-manager method.
    def manager_label
      package_manager == :brew ? "Homebrew" : package_manager.to_s.presence || "Package manager"
    end

    # Does Homebrew have a ready-made build (a "bottle") of `formula` for
    # THIS macOS and chip? true / false, or nil when we can't tell (no
    # Homebrew, or brew failed). Homebrew stops making bottles for macOS
    # releases it no longer supports, and without one `brew install`
    # compiles the formula and its dependencies from source — for ffmpeg
    # that's dozens of libraries and can take an hour.
    #
    # Asks brew itself rather than keeping a table of supported macOS
    # versions here: `brew info --json=v2` lists only the bottles that fit
    # this machine, so an empty list means "would build from source".
    # Cached for a few minutes because each call costs about half a second.
    def homebrew_bottle?(formula)
      return nil unless package_manager == :brew

      self.class.bottle_cache.fetch(formula) do
        brew = self.class.find_executable("brew") or return nil
        out, _err, status = self.class.run(
          brew, "info", "--json=v2", formula,
          env: { "HOMEBREW_NO_AUTO_UPDATE" => "1", "HOMEBREW_NO_ENV_HINTS" => "1" },
          timeout: 20
        )
        result =
          if status&.success?
            # Only the bottles that fit this machine are listed. On a macOS
            # Homebrew has dropped, "bottle" comes back as {} — no ready-made
            # build, so it would compile from source.
            files = JSON.parse(out).dig("formulae", 0, "bottle", "stable", "files")
            files.is_a?(Hash) && files.any?
          end
        self.class.bottle_cache.store(formula, result)
      end
    rescue JSON::ParserError, SystemCallError
      nil
    end

    # Formula → [answer, time]. Small and per-process; entries expire.
    class BottleCache
      TTL = 600

      def initialize = @entries = {}

      def fetch(formula)
        answer, at = @entries[formula]
        return answer if at && Time.now - at < TTL

        yield
      end

      def store(formula, answer)
        @entries[formula] = [ answer, Time.now ]
        answer
      end

      def clear = @entries.clear
    end

    def self.bottle_cache = (@bottle_cache ||= BottleCache.new)

    def self.detect_os
      case RbConfig::CONFIG["host_os"]
      when /darwin/i then :macos
      when /linux/i  then :linux
      else :unknown
      end
    end

    def self.detect_arch
      case RbConfig::CONFIG["host_cpu"].to_s
      when /arm64|aarch64/i then :arm64
      when /x86_64|amd64/i  then :x86_64
      end
    end

    # macOS: "14.8.5" (sw_vers). Linux: the distro's own name for itself,
    # "Ubuntu 24.04.1 LTS" (/etc/os-release). nil when unknown.
    def self.detect_os_version(os)
      case os
      when :macos
        out, _err, status = run("/usr/bin/sw_vers", "-productVersion", timeout: 5)
        out.strip.presence if status&.success?
      when :linux
        File.read("/etc/os-release")[/^PRETTY_NAME="?([^"\n]+)"?/, 1] if File.readable?("/etc/os-release")
      end
    rescue SystemCallError
      nil
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
      dirs += [ "/opt/homebrew/bin", "/usr/local/bin" ] if cmd == "brew"
      dirs.any? { |dir| !dir.to_s.empty? && File.executable?(File.join(dir, cmd)) }
    end

    # Directories checked after PATH when looking for a tool Roe runs by full
    # path (ffmpeg). A server started outside a login shell can have a PATH
    # without Homebrew's bin dirs, and /usr/local/bin is where standalone
    # macOS builds are usually dropped.
    EXTRA_BIN_DIRS = [ "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin" ].freeze

    # Where `roe install` puts tools it downloads itself: ~/.roe/tools,
    # shared by every site on this computer (ROE_TOOLS_DIR overrides it).
    def self.tools_dir
      ENV["ROE_TOOLS_DIR"].presence ||
        File.join(ENV["ROE_HOME"].presence || File.join(Dir.home, ".roe"), "tools")
    end

    # mise's shims run whichever version the global mise config names, so a
    # tool added with `mise use -g` is found here even by a server that was
    # started before it was installed.
    def self.mise_shims_dir
      data = ENV["MISE_DATA_DIR"].presence ||
             File.join(ENV["XDG_DATA_HOME"].presence || File.join(Dir.home, ".local", "share"), "mise")
      File.join(data, "shims")
    end

    # Every directory searched for a program, in order: `first` (a tool's
    # own download folder), PATH, the usual bin dirs, then mise's shims.
    def self.search_dirs(first: [])
      (Array(first) + ENV.fetch("PATH", "").split(File::PATH_SEPARATOR) + EXTRA_BIN_DIRS + [ mise_shims_dir ])
        .reject { |dir| dir.to_s.empty? }.uniq
    end

    # Full path to an executable named `cmd`, or nil. A pure scan — never
    # runs anything.
    def self.find_executable(cmd, first: [])
      search_dirs(first: first).each do |dir|
        path = File.join(dir, cmd)
        return path if File.file?(path) && File.executable?(path)
      end
      nil
    end

    # Where mise is, if it's installed: PATH, or its installer's default
    # ~/.local/bin, which a non-login shell's PATH can miss.
    def self.mise_path
      find_executable("mise", first: [ File.join(Dir.home, ".local", "bin") ])
    end

    # Run a program with arguments (never through a shell). Returns
    # [stdout, stderr, Process::Status], or [stdout, stderr, nil] if it ran
    # past `timeout` seconds and was killed.
    def self.run(*cmd, timeout:, env: {})
      Open3.popen3(env, *cmd) do |stdin, out, err, wait|
        stdin.close
        readers = [ Thread.new { out.read }, Thread.new { err.read } ]
        status =
          if wait.join(timeout)
            wait.value
          else
            begin
              Process.kill("KILL", wait.pid)
            rescue Errno::ESRCH
              nil
            end
            wait.join
            nil
          end
        readers.each { |t| t.join(1) }
        [ readers[0].value.to_s, readers[1].value.to_s, status ]
      end
    end
  end
end
