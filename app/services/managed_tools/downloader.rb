require "net/http"
require "uri"
require "digest"
require "zip"

module ManagedTools
  # Downloads a pinned, checksummed build of a program into
  # Platform.tools_dir (~/.roe/tools/<tool>/<version>) — for tools that can
  # be installed without a package manager. `roe install` uses it when
  # Homebrew or apt isn't an option (an older macOS, no admin rights).
  #
  # The version, URLs and SHA-256 checksums are fixed in code, never
  # "latest", and a download that doesn't match is thrown away: these are
  # programs Roe will run on files people upload.
  #
  # Each tool's builds live in its BUILDS table:
  #   { [os, arch] => [ { url:, sha256: }, … ] }   (one zip per program)
  #
  # The production in-app install (parked for 0.5.0) is meant to reuse this
  # with a different destination (/data/tools).
  class Downloader
    class Error < StandardError; end

    OPEN_TIMEOUT  = 15
    READ_TIMEOUT  = 120
    MAX_REDIRECTS = 5

    attr_reader :tool, :version, :builds, :root

    # progress: optional callable, called with (filename, bytes_so_far,
    # total_bytes_or_nil) while downloading.
    def initialize(tool:, version:, builds:, root: Platform.tools_dir, progress: nil)
      @tool = tool.to_s
      @version = version
      @builds = builds
      @root = root
      @progress = progress
    end

    # The folder this version's programs end up in.
    def bin_dir = File.join(root, tool, version)

    def files_for(platform)
      builds[[ platform.os, platform.arch ]]
    end

    def available_for?(platform) = files_for(platform).present?

    # Download, check, unpack and test. Returns bin_dir. Raises Error with a
    # plain-words message on anything that goes wrong, and leaves nothing
    # half-installed behind.
    def install!(platform)
      files = files_for(platform) or
        raise Error, "There's no ready-made #{tool} download for #{platform.system_label}."

      FileUtils.mkdir_p(File.join(root, tool))
      staging = Dir.mktmpdir("#{tool}-", File.join(root, tool))
      begin
        files.each { |file| fetch_and_unpack(file, staging) }
        programs = Dir.children(staging).select { |name| File.file?(File.join(staging, name)) }
        raise Error, "The download didn't contain any programs." if programs.empty?

        programs.each { |name| prepare_program(File.join(staging, name), platform) }
        FileUtils.rm_rf(bin_dir)
        File.rename(staging, bin_dir)
        bin_dir
      ensure
        FileUtils.rm_rf(staging) if staging && File.exist?(staging)
      end
    end

    # Remove every downloaded version except this one.
    def remove_other_versions!
      Dir.glob(File.join(root, tool, "*")).each do |dir|
        FileUtils.rm_rf(dir) unless File.basename(dir) == version || File.basename(dir).start_with?("#{tool}-")
      end
    end

    private

    def fetch_and_unpack(file, staging)
      zip_path = File.join(staging, ".#{File.basename(URI(file[:url]).path)}")
      download(file[:url], zip_path)

      actual = Digest::SHA256.file(zip_path).hexdigest
      unless actual == file[:sha256]
        raise Error, "#{File.basename(zip_path).delete_prefix('.')} didn't match its checksum, so it was thrown away. Try again later, or use another install method."
      end

      Zip::File.open(zip_path) do |zip|
        zip.each do |entry|
          next unless entry.file?

          name = File.basename(entry.name)
          next if name.start_with?(".") || entry.name.include?("__MACOSX")

          File.binwrite(File.join(staging, name), entry.get_input_stream.read)
        end
      end
    ensure
      FileUtils.rm_f(zip_path) if zip_path
    end

    def prepare_program(path, platform)
      File.chmod(0o755, path)
      # A file downloaded by Ruby isn't quarantined the way a browser
      # download is, but clear the flag anyway in case the folder inherits
      # one, so macOS doesn't refuse to run it.
      if platform.macos?
        Platform.run("/usr/bin/xattr", "-d", "com.apple.quarantine", path, timeout: 10)
      end
      _out, err, status = Platform.run(path, "-version", timeout: 20)
      return if status&.success?

      raise Error, "#{File.basename(path)} was downloaded but won't run on this computer. #{err.lines.first.to_s.strip}".strip
    end

    # Stream to disk (the ffmpeg zips are ~30 MB each), following redirects.
    def download(url, dest, redirects_left: MAX_REDIRECTS)
      uri = URI.parse(url)
      raise Error, "Refusing a non-HTTPS download: #{url}" unless uri.scheme == "https"

      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "Roe (roe install #{tool})"
        http.request(request) do |response|
          case response
          when Net::HTTPSuccess
            write_body(response, dest, File.basename(uri.path))
          when Net::HTTPRedirection
            raise Error, "Too many redirects downloading #{tool}." if redirects_left <= 0

            location = URI.join(url, response["location"]).to_s
            return download(location, dest, redirects_left: redirects_left - 1)
          else
            raise Error, "The #{tool} download failed (#{response.code} #{response.message})."
          end
        end
      end
    rescue SocketError, Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Error, "Couldn't download #{tool}: #{e.message}. Check your internet connection."
    end

    def write_body(response, dest, name)
      total = response["content-length"]&.to_i
      done = 0
      File.open(dest, "wb") do |f|
        response.read_body do |chunk|
          f.write(chunk)
          done += chunk.bytesize
          @progress&.call(name, done, total)
        end
      end
    end
  end
end
