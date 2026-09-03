# frozen_string_literal: true

# Where a member page actually lives, asked from anywhere.
#
# Every member page is an ordinary Page whose URL comes from its `url_name`, so
# a site owner can rename sign-in to /login or /members/enter at any time. The
# block renderers hardcoded "/sign-in", "/sign-up" and "/upgrade", and
# config/routes.rb carries redirect aliases pinned to the same strings — so a
# rename silently 404s the paywall button, the signup block's static fallback,
# and the checkout form, with no way to find them but grep.
#
# The lookup already existed as AdminHelper#find_member_page, reachable only
# from a view. Model code needs the same answer.
class MemberPages
  # stem → the file Roe installs it as. Both locations are checked because a
  # page can be moved out of members/ and still work.
  STEMS = %w[signin signup upgrade donate unsubscribe account].freeze

  # What Roe ships each page's url_name as, used only when the page is absent.
  # Written out rather than derived: "signin" ships as /sign-in and "signup" as
  # /sign-up, and no rule turns one into the other — deriving it produced
  # /signup, which is a different, already-taken route.
  CONVENTIONAL = {
    "signin" => "/sign-in",
    "signup" => "/sign-up",
    "upgrade" => "/upgrade",
    "donate" => "/donate",
    "unsubscribe" => "/unsubscribe",
    "account" => "/account"
  }.freeze

  class << self
    # The page's path, or nil when the site hasn't got one. Nil matters: a link
    # to a page that doesn't exist is worse than no link, so callers decide
    # what to do rather than being handed a guess.
    def url_for(stem)
      page = find(stem)
      return nil unless page

      "/#{page.url_name}"
    end

    # Falls back to the conventional path when the page is missing, for callers
    # that must render something. Prefer url_for and handle nil where you can.
    def url_for!(stem, fallback: nil)
      url_for(stem) || fallback || CONVENTIONAL[stem.to_s] || "/#{stem}"
    end

    def exists?(stem) = find(stem).present?

    def find(stem)
      root = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "pages"))
      [ root.join("members", "#{stem}.md"), root.join("#{stem}.md") ]
        .filter_map { |path| Page.find_by(file_path: path.to_s) }
        .first
    rescue StandardError => e
      Rails.logger.warn "[MemberPages] lookup failed for #{stem}: #{e.message}"
      nil
    end
  end
end
