module ManagedTools
  # libvips — the native image library behind ruby-vips / image_processing.
  # Roe uses it to generate optimized, resized image variants on upload.
  # Optional: without it, images are served at full size (see
  # ImageVariantGenerator.available?, which uses the same detection).
  class Libvips < Tool
    def key      = :libvips
    def label    = "libvips"
    def summary  = "Fast native image-processing library"
    def why      = "Roe uses libvips to resize and optimize images when you upload them. Without it, images still work but are served at full size."
    def docs_url = "https://www.libvips.org/install.html"

    # Package names vary by manager: "vips" on Homebrew/Fedora/Arch-ish,
    # "libvips" on Debian/Ubuntu/Alpine, "libvips-tools" on openSUSE.
    def packages
      {
        brew:   "vips",
        apt:    "libvips",
        dnf:    "vips",
        yum:    "vips",
        pacman: "libvips",
        zypper: "libvips-tools",
        apk:    "vips",
      }
    end

    # The gem can be installed while the native library is missing, so we
    # actually touch Vips rather than trusting the require alone. Mirrors
    # ImageVariantGenerator.available?. Never raises.
    def installed?
      require "ruby-vips"
      Vips.respond_to?(:version_string) && !Vips.version_string.to_s.empty?
    rescue LoadError, NameError
      false
    rescue => e
      Rails.logger.debug { "[ManagedTools::Libvips] detection error: #{e.message}" }
      false
    end

    def version
      require "ruby-vips"
      Vips.version_string
    rescue StandardError
      nil
    end
  end
end
