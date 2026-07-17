# Single source of truth for new-content templates.
#
# Each content type (post/page/product) has an editable template at
# site/system/templates/<type>_template.md — optional frontmatter defaults plus
# a starter body. The canonical versions ship in the install kit (see KIT_DIR)
# and are copied there on install; a fresh install falls back to the kit file
# until it saves its own.
#
# Some fields are REQUIRED: they're always present in new content and shown as
# a locked "always included" list in the template editor. `frontmatter_for`
# re-adds any the saved template dropped, so new content can never start
# without them.
#
# Both the template editors (Admin::SettingsController) and the create actions
# read through here so the two never drift.
module ContentTemplate
  TYPES = %w[post page product].freeze

  # Always-required field names, with shipped default values. Order matters —
  # it's the order they appear (first) in new frontmatter and in the editor's
  # locked list. `date` is stamped fresh at create time.
  REQUIRED = {
    "post"    => { "title" => nil, "date" => nil, "status" => "draft" },
    "page"    => { "title" => nil, "status" => "draft" },
    "product" => { "title" => nil, "category" => nil, "status" => "draft",
                   "price" => "0.00", "sku" => nil, "image" => nil }
  }.freeze

  # The canonical shipped templates are files in the install kit. New installs
  # copy them to site/system/templates/ (SiteTemplates::Loader); to change what
  # ships with Roe, edit those files:
  #
  #   lib/site_templates/minimum/system/templates/<type>_template.md
  #
  # They hold OPTIONAL defaults + a starter body only — required fields are
  # added separately (see .frontmatter_for) and never live here.
  KIT_DIR = Rails.root.join("lib", "site_templates", "minimum", "system", "templates")

  def self.type?(type)
    TYPES.include?(type.to_s)
  end

  def self.dir
    File.join(RoeSitePaths::SITE_PATH, "system", "templates")
  end

  def self.path(type)
    File.join(dir, "#{type}_template.md")
  end

  def self.required_names(type)
    REQUIRED.fetch(type.to_s, {}).keys
  end

  # The editable template's raw content: the install's own file, falling back to
  # the canonical kit template when the install is missing it.
  def self.template_content(type)
    site = path(type)
    return File.read(site) if File.exist?(site)

    kit = KIT_DIR.join("#{type}_template.md")
    kit.file? ? kit.read : ""
  end

  def self.save_template(type, content)
    FileUtils.mkdir_p(dir)
    File.write(path(type), content.to_s)
  end

  # Frontmatter (Hash) and body (String) for a new item of this type:
  # required defaults first (guaranteed present, in order), then the editable
  # template's optional fields, then caller overrides (title, url_name, …). A
  # fresh `date` is stamped for posts.
  def self.frontmatter_for(type, overrides = {})
    metadata = REQUIRED.fetch(type.to_s, {}).dup

    parsed   = FrontMatterParser::Parser.new(:md).call(template_content(type))
    optional = parsed.front_matter.is_a?(Hash) ? parsed.front_matter : {}
    metadata.merge!(optional)

    # Stamp `date` last so a stale `date:` in a saved template can never win.
    metadata["date"] = Time.current.strftime("%Y-%m-%dT%H:%M") if REQUIRED.fetch(type.to_s, {}).key?("date")

    metadata.merge!(overrides.transform_keys(&:to_s))
    [ metadata, parsed.content ]
  end
end
