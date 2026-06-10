require "erb"

# SiteTemplates::Loader installs a folder of templates from
# lib/site_templates/ into a destination directory. The folder's layout
# mirrors /site, so a file at `<folder>/system/global/site.yml` lands
# at /site/system/global/site.yml. Files that already exist at the
# destination are NEVER touched, so:
#
#   * The same folder can be installed twice (no-op on the second run).
#   * Two folders can be installed in sequence — files added by the
#     second never overwrite files placed by the first or by the user.
#   * Hand-edited content is preserved across re-installs.
#
# Source folders are called whatever fits their purpose at the caller
# site — "kits" (curated starter packs like minimum / blog_kit) and
# "features" (toggleable bundles like members / store / podcast) both
# live under lib/site_templates/ and both go through this same loader.
#
# File naming:
#   * Files ending in `.erb` are ERB-rendered with the supplied `locals`
#     hash and written WITHOUT the `.erb` suffix (so
#     `posts/welcome.md.erb` ships as `posts/welcome.md`).
#   * All other files are copied byte-for-byte — safe for binary assets.
module SiteTemplates
  class Loader
    TEMPLATES_ROOT = Rails.root.join("lib", "site_templates")

    def self.install(folder:, destination: RoeSitePaths::SITE_PATH, locals: {}, skip: [])
      new(folder: folder, destination: destination, locals: locals, skip: skip).install
    end

    # Read a single `.erb` template from a folder, ERB-render with
    # `locals`, and return the rendered string. Caller writes it
    # wherever they want — used for the small set of files that admin
    # actions intentionally overwrite (members.yml, store.yml,
    # podcast.yml). The loader itself never overwrites; this method
    # just renders.
    def self.render(folder:, template:, locals: {})
      path = TEMPLATES_ROOT.join(folder.to_s, template)
      unless path.file?
        raise ArgumentError, "Template not found: #{path}"
      end
      ERB.new(path.read, trim_mode: "-").result_with_hash(locals)
    end

    def initialize(folder:, destination:, locals: {}, skip: [])
      @folder      = folder.to_s
      @folder_path = TEMPLATES_ROOT.join(@folder)
      @destination = Pathname.new(destination)
      @locals      = locals
      # Relative target paths (e.g. "posts/welcome.md") the caller has
      # decided NOT to install even though the file is missing — used by
      # callers that need to honour a "user deliberately doesn't want
      # this file" signal the loader itself can't detect.
      @skip        = Array(skip).map(&:to_s)
    end

    def install
      unless @folder_path.directory?
        raise ArgumentError, "Site template folder not found: #{@folder_path}"
      end

      installed = []
      skipped   = []

      template_files.each do |source|
        target          = target_path_for(source)
        relative_target = target.relative_path_from(@destination).to_s

        if target.exist? || @skip.include?(relative_target)
          skipped << target.to_s
          next
        end

        target.dirname.mkpath
        write_target(source, target)
        installed << target.to_s
      end

      { installed: installed, skipped: skipped }
    end

    private

    def template_files
      Pathname.glob(@folder_path.join("**", "*")).select(&:file?)
    end

    def target_path_for(source)
      relative = source.relative_path_from(@folder_path).to_s.sub(/\.erb\z/, "")
      @destination.join(relative)
    end

    def write_target(source, target)
      if source.to_s.end_with?(".erb")
        rendered = ERB.new(source.read, trim_mode: "-").result_with_hash(@locals)
        target.write(rendered)
      else
        # binwrite handles text and binary identically — no encoding
        # conversion, no surprise CRLF translation.
        target.binwrite(source.binread)
      end
    end
  end
end
