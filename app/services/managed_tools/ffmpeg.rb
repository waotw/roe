require "open3"

module ManagedTools
  # ffmpeg — the command-line video tool. Roe uses it on the local install to
  # make small web versions of uploaded videos (and ffprobe, which ships in
  # the same package, to read a video's length, size and rotation).
  #
  # Optional: without it, videos are served exactly as uploaded. For 0.4.0
  # it's expected on the local machine only — video is optimised there and
  # sent to the live site with Site Sync — so it isn't in the Dockerfile.
  #
  # Like the Stripe CLI this is a program Roe runs, not a library it links,
  # so detection finds the executables. Unlike the Stripe CLI, Roe runs them
  # by full path, so a server started without Homebrew's bin dirs on PATH
  # still finds them (Platform.find_executable).
  #
  # Three ways in, best first (install_methods): the system package manager
  # when it has a ready-made build, a direct download into ~/.roe/tools,
  # and mise. `roe install ffmpeg` walks them in that order.
  class Ffmpeg < Tool
    # A probe of `ffmpeg -version` should come back instantly; anything slower
    # means a broken or hung binary, which counts as "not installed".
    VERSION_TIMEOUT = 5

    # The direct download: Martin Riedl's static release builds (ffmpeg and
    # ffprobe as separate zips, each one self-contained program, with
    # libx264 and AAC). Pinned — bump the version, URLs and checksums
    # together, from https://ffmpeg.martin-riedl.de (each zip has a
    # .sha256 next to it).
    DOWNLOAD_VERSION = "9.0.2".freeze
    DOWNLOAD_BASE = "https://ffmpeg.martin-riedl.de/download".freeze
    DOWNLOAD_BUILDS = {
      [ :macos, :arm64 ] => [
        { url: "#{DOWNLOAD_BASE}/macos/arm64/1789931890_9.0.2/ffmpeg.zip",  sha256: "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924" },
        { url: "#{DOWNLOAD_BASE}/macos/arm64/1789931890_9.0.2/ffprobe.zip", sha256: "fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6" }
      ],
      [ :macos, :x86_64 ] => [
        { url: "#{DOWNLOAD_BASE}/macos/amd64/1789931006_9.0.2/ffmpeg.zip",  sha256: "7c6b4125b191cbf773832dc51f424cf2b6bb7da43007d1e066f95909e47cacd4" },
        { url: "#{DOWNLOAD_BASE}/macos/amd64/1789931006_9.0.2/ffprobe.zip", sha256: "2322438ed2f6319a691291b247d09c69dcaa3a982460d1f269a7e1af335cfdfd" }
      ],
      [ :linux, :x86_64 ] => [
        { url: "#{DOWNLOAD_BASE}/linux/amd64/1789931100_9.0.2/ffmpeg.zip",  sha256: "fa8ecf4abbd290d98f7d188b8649cc6b391ae209a98452be955a15aab1909d7f" },
        { url: "#{DOWNLOAD_BASE}/linux/amd64/1789931100_9.0.2/ffprobe.zip", sha256: "3f428c49070be3d24ec338602b76d412e401ffcb8a5641ef0e729181a232fc32" }
      ],
      [ :linux, :arm64 ] => [
        { url: "#{DOWNLOAD_BASE}/linux/arm64/1789931697_9.0.2/ffmpeg.zip",  sha256: "93a76ae90db5474eecdf951a729857c64f3de23567228d6a7d5e6e8e3cd1021b" },
        { url: "#{DOWNLOAD_BASE}/linux/arm64/1789931697_9.0.2/ffprobe.zip", sha256: "bcbe80fb741c180083327afaf5434812e006b33cacde2016b9aeaf6936128330" }
      ]
    }.freeze

    # mise's conda backend: a ready-made ffmpeg (with ffprobe) for any macOS
    # or Linux, no admin rights — but it brings its own copy of every
    # library, about 400 MB.
    MISE_TOOL = "conda:ffmpeg".freeze

    def key      = :ffmpeg
    def label    = "ffmpeg"
    def summary  = "Video conversion tool"
    def why      = "Roe uses ffmpeg to make smaller, faster-loading web versions of the videos you upload, and to read their length. Without it, videos still work but are served exactly as uploaded, which can be very large. Install it on the computer where you write; videos are sent to your live site with Site Sync."
    def docs_url = "https://ffmpeg.org/download.html"

    # The package is named ffmpeg everywhere we detect. It includes ffprobe.
    # (Fedora and openSUSE ship a reduced build in their main repos; the full
    # one comes from RPM Fusion / Packman. The install guide link covers it.)
    def packages
      %i[brew apt dnf yum pacman zypper apk].index_with { "ffmpeg" }
    end

    def downloader(progress: nil)
      Downloader.new(tool: key, version: DOWNLOAD_VERSION, builds: DOWNLOAD_BUILDS, progress: progress)
    end

    def ffmpeg_path  = programs["ffmpeg"]
    def ffprobe_path = programs["ffprobe"]

    # Both programs must be present and actually run. ffprobe is checked too
    # because everything that reads a video (length, size, rotation) uses
    # it, and a standalone ffmpeg download doesn't always come with it.
    # Never raises.
    def installed?
      [ ffmpeg_path, ffprobe_path ].all? { |path| path && runs?(path) }
    rescue => e
      Rails.logger.debug { "[ManagedTools::Ffmpeg] detection error: #{e.message}" }
      false
    end

    # What's missing, for a clearer message than "not installed" when only
    # one of the two programs is there. [] when both are present.
    def missing
      { "ffmpeg" => ffmpeg_path, "ffprobe" => ffprobe_path }.reject { |_, path| path }.keys
    end

    # Shown on the Tools page when only one of the two is found — typically
    # a standalone ffmpeg download without its ffprobe.
    def note
      gone = missing
      return nil unless gone.one?

      "Found #{(%w[ffmpeg ffprobe] - gone).first} but not #{gone.first}. Roe needs both; installing the ffmpeg package gives you both."
    end

    # "8.0.1", or a build id like "N-121489-g7f7335ec43" for snapshot builds.
    # Some builders append their web address ("9.0.2-https://…"); dropped.
    def version
      path = ffmpeg_path or return nil
      out, status = self.class.capture(path, "-version", timeout: VERSION_TIMEOUT)
      return nil unless status&.success?

      out.to_s[/\Affmpeg version (\S+)/, 1]&.sub(/-https?:.*\z/, "")
    rescue StandardError
      nil
    end

    # Package manager when it has a ready-made build, then the direct
    # download, then mise.
    def install_methods(platform = Platform.current)
      [ package_manager_method(platform), download_method(platform), mise_method(platform) ]
    end

    # Run a program with arguments (never through a shell) and return
    # [combined output, Process::Status]. Kills it and returns [output, nil]
    # if it runs past `timeout` seconds.
    def self.capture(*cmd, timeout:)
      Open3.popen2e(*cmd) do |stdin, out, wait|
        stdin.close
        reader = Thread.new { out.read }
        if wait.join(timeout)
          [ reader.value, wait.value ]
        else
          begin
            Process.kill("KILL", wait.pid)
          rescue Errno::ESRCH
            nil
          end
          wait.join
          reader.join(1)
          [ reader.value.to_s, nil ]
        end
      end
    end

    private

    # ffmpeg and ffprobe from the SAME folder when one has both, so a stray
    # ffmpeg on its own (an old download in /usr/local/bin) doesn't get
    # paired with an ffprobe of a different version from somewhere else.
    # Roe's own download folder is searched first.
    def programs
      dirs = Platform.search_dirs(first: [ downloader.bin_dir ])
      both = dirs.find { |dir| %w[ffmpeg ffprobe].all? { |name| executable?(File.join(dir, name)) } }
      return { "ffmpeg" => File.join(both, "ffmpeg"), "ffprobe" => File.join(both, "ffprobe") } if both

      %w[ffmpeg ffprobe].index_with { |name| Platform.find_executable(name, first: [ downloader.bin_dir ]) }
    end

    def executable?(path) = File.file?(path) && File.executable?(path)

    # Homebrew without a ready-made build would compile ffmpeg and dozens
    # of libraries; the download is a better way in.
    def build_from_source_ok? = false

    def download_method(platform)
      if downloader.available_for?(platform)
        InstallMethod.new(
          key: :download, label: "Direct download", usable: true, sudo: false, restart: false,
          detail: "ffmpeg and ffprobe #{DOWNLOAD_VERSION}, about 130 MB, into #{display_path(downloader.bin_dir)}"
        )
      else
        InstallMethod.new(key: :download, label: "Direct download", usable: false,
                          reason: "There's no ready-made download for #{platform.system_label}.")
      end
    end

    def mise_method(_platform)
      if Platform.mise_path
        InstallMethod.new(
          key: :mise, label: "mise", command: "mise use -g #{MISE_TOOL}", usable: true, sudo: false,
          restart: false, detail: "a ready-made build with its own libraries, about 400 MB"
        )
      else
        InstallMethod.new(key: :mise, label: "mise", usable: false, reason: "mise isn't installed.")
      end
    end

    def display_path(path) = path.sub(/\A#{Regexp.escape(Dir.home)}/, "~")

    def runs?(path)
      _out, status = self.class.capture(path, "-version", timeout: VERSION_TIMEOUT)
      status&.success? || false
    end
  end
end
