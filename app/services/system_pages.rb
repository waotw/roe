# Pages Roe shows at a step of its own: a failed sign-in, a finished
# checkout, "View all" on a collection with no filters. Found the way
# MemberPages finds the member pages, so a page can be renamed, retitled or
# given any url_name and still be found:
#
#   1. page_type    — `page_type: checkout-success`. Survives everything.
#   2. its file     — the one Roe installs: pages/members/checkout-success.md
#                     (or pages/checkout-success.md).
#   3. its url_name — what every site before page_type relied on.
#
# The home page is one of them: `page_type: home` lets it have any file
# name and url_name and still be the page at `/` (Page.home).
#
# signin, signup, upgrade, donate and unsubscribe go through MemberPages, which also
# recognises a page by the form it carries.
#
# Changing a page's page_type is the one way to lose it, so the page editor
# warns about it (shared/_metadata_editor).
module SystemPages
  # page_type => when Roe shows it, the file it's installed as, and the
  # url_name it was found by before page_type.
  TYPES = {
    "home" => { purpose: "as the home page, at /", file: "home", url_name: "home" },
    "signin" => { purpose: "for signing in", file: "signin", url_name: "sign-in" },
    "signup" => { purpose: "for signing up", file: "signup", url_name: "sign-up" },
    "upgrade" => { purpose: "for upgrading a membership", file: "upgrade", url_name: "upgrade" },
    "donate" => { purpose: "for donations", file: "donate", url_name: "donate" },
    "check-email" => { purpose: "after someone asks for a sign-in link", file: "check-email", url_name: "check-email" },
    "recovery" => { purpose: "for account recovery", file: "recover-account", url_name: "recover-account" },
    "unsubscribe" => { purpose: "when someone unsubscribes", file: "unsubscribe", url_name: "unsubscribe" },
    "unsubscribed" => { purpose: "after someone unsubscribes", file: "unsubscribed", url_name: "unsubscribed" },
    "checkout-success" => { purpose: "after a checkout", file: "checkout-success", url_name: "checkout-success" },
    "checkout-cancel" => { purpose: "when a checkout is cancelled", file: "checkout-cancel", url_name: "checkout-cancel" },
    "donation-success" => { purpose: "after a donation", file: "donation-success", url_name: "donation-success" },
    "donation-cancel" => { purpose: "when a donation is cancelled", file: "donation-cancel", url_name: "donation-cancel" },
    "archive" => { purpose: "as \"View all\" for a collection with no filters", file: "archive", url_name: "archive" }
  }.freeze

  module_function

  # The page Roe shows for this type, or nil.
  def find(type)
    type = type.to_s
    spec = TYPES.fetch(type)
    found = MemberPages::STEMS.include?(type) ? MemberPages.find(type) : (declared(type) || installed(spec[:file]))
    found || by_url_name(spec[:url_name])
  rescue StandardError => e
    Rails.logger.warn "[SystemPages] lookup failed for #{type}: #{e.message}"
    nil
  end

  # Where the page lives now, or `fallback` when the site hasn't got one.
  def path(type, fallback: nil)
    find(type)&.public_url || fallback
  end

  # When Roe shows a page of this type, or nil if it isn't one of Roe's.
  def purpose(page_type) = TYPES.dig(page_type.to_s.strip, :purpose)

  def declared(type) = Page.where("json_extract(metadata, '$.page_type') = ?", type).first

  def installed(file)
    root = File.join(RoeSitePaths::SITE_PATH, "pages")
    [ File.join(root, "members", "#{file}.md"), File.join(root, "#{file}.md") ].each do |path|
      next unless File.file?(path)

      page = Page.find_by(file_path: RoeSitePaths.normalize(path))
      return page if page
    end
    nil
  end

  def by_url_name(name) = Page.find_by("json_extract(metadata, '$.url_name') = ?", name)
end
