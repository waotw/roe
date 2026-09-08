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
  # `account` is here for url_for!'s sake only: /account is a controller route
  # with an ERB view, not a Page, so find("account") never resolves and falls
  # through to CONVENTIONAL — which is the real route, so callers get the right
  # answer by a different path than the rest.
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

    # Member pages whose absence actually breaks something, given what's turned
    # on. Deliberately not "every stem Roe ships" — a site with donations off
    # has no use for a donate page, and reporting it as missing would train
    # people to ignore the warning.
    #
    # signin and signup are unconditional: with Members enabled and neither
    # page resolvable, nobody can get in or sign up, and nothing else on the
    # site says so.
    def required_stems
      return [] unless SiteFeature.members_enabled?

      stems = %w[signin signup]
      stems << "unsubscribe" if SiteFeature.newsletters_feature_enabled?
      stems << "upgrade"     if SiteFeature.memberships_enabled?
      stems << "donate"      if SiteFeature.donations_enabled?
      stems
    end

    # Required, and nowhere to be found at all — not declared, not at the
    # conventional filename, and no page anywhere carrying the form. Members
    # genuinely cannot do this thing.
    def missing = required_stems.reject { |stem| resolve(stem).found? }

    # Required, and working only because some page happens to contain the form.
    # The site functions, so this isn't breakage — but the dedicated page is
    # gone, the link now points somewhere incidental, and the next edit to that
    # page could take it away without anyone connecting the two.
    #
    # Returns { stem => page } so the warning can name what Roe settled on.
    def guessed
      required_stems.each_with_object({}) do |stem, out|
        resolution = resolve(stem)
        out[stem] = resolution.page if resolution.guessed?
      end
    end

    # Three kinds of evidence, cheapest and most explicit first.
    #
    #   declared     — page_type: signin. Survives every rename.
    #   demonstrated — the page renders a `form for: signin`. Survives the
    #                  declaration being removed, because it's derived from what
    #                  the page actually does.
    #   conventional — the filename Roe ships. Covers every page written before
    #                  page_type existed, so no install has to migrate.
    #
    # Looking only at the filename is what broke: a sign-in page recreated in
    # the admin is titled "Sign In", which parameterizes to sign-in.md, and the
    # lookup went blind — no sign-in link anywhere, no explanation.
    # How the answer was arrived at, not just what it is. The two questions
    # differ: "can anyone sign in?" is answered by any page carrying the form,
    # while "which page IS the sign-in page?" needs a page that says so. A site
    # can be working and still have lost the page it was meant to work through.
    Resolution = Struct.new(:page, :how, keyword_init: true) do
      def found?   = page.present?
      def guessed? = how == :demonstrated
    end

    # Dedicated page first, incidental form last. A signup page that offers
    # "already a member? sign in" contains the form but isn't the sign-in page,
    # and pointing the account icon at it sends people somewhere arbitrary.
    def resolve(stem)
      if (page = declared(stem))
        Resolution.new(page: page, how: :declared)
      elsif (page = conventional(stem))
        Resolution.new(page: page, how: :conventional)
      elsif (page = demonstrated(stem))
        Resolution.new(page: page, how: :demonstrated)
      else
        Resolution.new(page: nil, how: nil)
      end
    rescue StandardError => e
      Rails.logger.warn "[MemberPages] lookup failed for #{stem}: #{e.message}"
      Resolution.new(page: nil, how: nil)
    end

    def find(stem) = resolve(stem).page

    private

    def declared(stem)
      Page.where("json_extract(metadata, '$.page_type') = ?", stem).first
    end

    # Only finds stems that are also form kinds — signin, signup, donate,
    # unsubscribe. There is no `for: upgrade` or `for: account` block, so those
    # two resolve by declaration or filename alone, which is why the templates
    # ship them with page_type set.
    #
    # Content is a database column, so this is one query rather than a file
    # walk. More than one page can carry the form — an upgrade page often does —
    # so order deterministically: the members folder first, then by path, so the
    # answer doesn't move around between requests.
    def demonstrated(stem)
      candidates = Page.where("content LIKE ?", "%for: #{stem}%").to_a
      return nil if candidates.empty?

      candidates.min_by do |page|
        [ page.file_path.to_s.include?("/pages/members/") ? 0 : 1, page.file_path.to_s ]
      end
    end

    def conventional(stem)
      root = Pathname.new(File.join(RoeSitePaths::SITE_PATH, "pages"))
      [ root.join("members", "#{stem}.md"), root.join("#{stem}.md") ]
        .filter_map { |path| Page.find_by(file_path: path.to_s) }
        .first
    end
  end
end
