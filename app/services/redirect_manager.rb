# frozen_string_literal: true

# Reads and writes the redirect rules in site/system/global/redirects.yml —
# the file SiteRedirectsMiddleware serves at request time.
#
# Built for the "renamed a published url_name" flow: when a post/page/product
# that the public could already reach changes its slug, Roe offers to record a
# 301 from the old path to the new one so inbound links don't 404. Writing the
# rule into redirects.yml (rather than a database column) keeps it:
#
#   * syncable — redirects.yml rides Site Sync to the live site like any other
#     content, so a redirect made locally reaches production (and vice versa);
#   * environment-free — production has its own database, so a DB column of
#     slug history wouldn't exist there; a file rule needs no history to serve;
#   * file-canonical — the YAML is the source of truth, matching the rest of
#     Roe.
#
# Deliberately matches the middleware's own shape: a top-level `redirects:` map
# of "from path" => { "to" => path, "status" => 301 }. Shorthand `from: to`
# (string value) is understood on read, but this service always WRITES the
# explicit hash form so later edits are unambiguous.
class RedirectManager
  CONFIG_PATH = File.join(RoeSitePaths::SITE_PATH, "system", "global", "redirects.yml").freeze

  Result = Struct.new(:written, :from, :to, :flattened, keyword_init: true)

  def self.add_301(from:, to:) = new.add_301(from: from, to: to)
  def self.rules = new.rules

  # Add (or update) a 301 from `from` to `to`.
  #
  # No-ops and returns written:false when:
  #   * from/to are blank or identical, or
  #   * an identical rule already exists.
  #
  # Chain flattening: renaming A→B then B→C must not leave A pointing at the
  # now-dead B. Any existing rule whose target is `from` is repointed to `to`,
  # so every old path lands on the current one in a single hop. The middleware
  # bails on a self-referential rule, but we also drop a would-be `to => to`
  # here so it never gets written.
  def add_301(from:, to:)
    from = normalize_path(from)
    to   = normalize_path(to)
    return Result.new(written: false, from: from, to: to, flattened: 0) if from.blank? || to.blank? || from == to

    data   = read
    redirects = data["redirects"].is_a?(Hash) ? data["redirects"].dup : {}

    # Flatten: repoint anything that currently targets `from` → `to`.
    flattened = 0
    redirects.each do |key, val|
      next if key == from
      current_to = val.is_a?(Hash) ? val["to"] : val
      if current_to == from
        redirects[key] = { "to" => to, "status" => 301 }
        flattened += 1
      end
    end

    # Drop a rule that would now point to itself (e.g. C was renamed back).
    redirects.delete(to)

    new_rule = { "to" => to, "status" => 301 }
    already  = redirects[from] == new_rule
    redirects[from] = new_rule

    data["redirects"] = redirects
    written = SiteFile.write(CONFIG_PATH, dump(data))
    reload! if written

    Result.new(written: written && !already, from: from, to: to, flattened: flattened)
  end

  def rules
    r = read["redirects"]
    r.is_a?(Hash) ? r : {}
  end

  private

  def read
    data = (SiteFile.read_yaml(CONFIG_PATH) if File.exist?(CONFIG_PATH))
    data.is_a?(Hash) ? data : {}
  rescue => e
    Rails.logger.error "[RedirectManager] couldn't read redirects.yml (#{e.message})"
    {}
  end

  # Match the file's existing style: no leading `---`, a single `redirects:`
  # map. Keeping it minimal keeps the file hand-editable.
  def dump(data)
    YAML.dump(data).sub(/\A---\s*\n/, "")
  end

  # Normalize to a root-relative, no-trailing-slash path the middleware matches
  # on (it chomps trailing slashes too). Leaves absolute off-site targets alone
  # — a redirect may legitimately point at another domain.
  def normalize_path(path)
    p = path.to_s.strip
    return p if p.empty? || p.match?(%r{\A https?:// }x)

    p = "/#{p}" unless p.start_with?("/")
    p = p.chomp("/")
    p.empty? ? "/" : p
  end

  def reload!
    SiteRedirectsMiddleware.reload! if defined?(SiteRedirectsMiddleware)
  end
end
