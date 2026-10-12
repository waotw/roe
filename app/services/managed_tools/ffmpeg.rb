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
  class Ffmpeg < Tool
    # A probe of `ffmpeg -version` should come back instantly; anything slower
    # means a broken or hung binary, which counts as "not installed".
    VERSION_TIMEOUT = 5

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

    def ffmpeg_path  = Platform.find_executable("ffmpeg")
    def ffprobe_path = Platform.find_executable("ffprobe")

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

    # Shown on the Dependencies page when only one of the two is found —
    # typically a standalone ffmpeg download without its ffprobe.
    def note
      gone = missing
      return nil unless gone.one?

      "Found #{(%w[ffmpeg ffprobe] - gone).first} but not #{gone.first}. Roe needs both; installing the ffmpeg package gives you both."
    end

    # "8.0.1", or a build id like "N-121489-g7f7335ec43" for snapshot builds.
    def version
      path = ffmpeg_path or return nil
      out, status = self.class.capture(path, "-version", timeout: VERSION_TIMEOUT)
      return nil unless status&.success?

      out.to_s[/\Affmpeg version (\S+)/, 1]
    rescue StandardError
      nil
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

    def runs?(path)
      _out, status = self.class.capture(path, "-version", timeout: VERSION_TIMEOUT)
      status&.success? || false
    end
  end
end
