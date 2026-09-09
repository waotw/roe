# Field definitions for the Music settings form (features/music.yml).
#
# One source of truth for what a release carries, in the order it renders,
# with the label, placeholder, hint and required flag for each. The form view
# reads this rather than hard-coding inputs, so adding a field is a change
# here and nowhere else — the pattern PodcastConfig::CANONICAL_FIELDS follows
# for shows.
#
# This is deliberately a subset of what a distributor asks for. The fields
# here are the ones Roe can show on a page or put in a feed; codes that only
# matter when handing a release to Spotify or Apple (UPC, ISRC, P-line/C-line
# split, contributor credits) are left out until something reads them, so the
# form doesn't collect data that goes nowhere.
class MusicConfigSchema
  # Release fields, in render order. `key` is the YAML key under
  # releases.<name>. `kind` drives which input the form draws:
  #   :text   — plain single-line input
  #   :image  — media path + picker/autocomplete + existence warning
  #   :date   — YYYY-MM-DD
  #   :select — one of `options`
  RELEASE_FIELDS = [
    { key: "title", label: "Title", kind: :text, required: true,
      placeholder: "Summer Release",
      hint: "The release name as people should read it. Title Case — stores reject all-caps." },

    { key: "artist", label: "Artist", kind: :text,
      placeholder: "Leave blank to use the artist above",
      hint: "Only when this release is by someone else." },

    { key: "release_date", label: "Release date", kind: :date,
      placeholder: "2026-06-01",
      hint: "YYYY-MM-DD." },

    { key: "cover", label: "Cover art", kind: :image,
      placeholder: "/media/images/summer-release-cover.jpg",
      hint: "Square artwork. 3000×3000 JPG or PNG is the distribution standard." },

    { key: "synopsis", label: "Synopsis", kind: :text,
      placeholder: "A short description of this release." },

    { key: "genre", label: "Genre", kind: :text,
      placeholder: "Electronic" },

    { key: "label", label: "Label", kind: :text,
      placeholder: "Leave blank if you're releasing it yourself" },

    { key: "copyright", label: "Copyright", kind: :text,
      placeholder: "℗ & © 2026 Your Name",
      hint: "℗ covers the recording, © the song. Most independent releases are the same name for both." },

    { key: "audience", label: "Audience", kind: :select, options: [ "", "free", "paid" ],
      hint: "Paid gates the release behind a membership. Needs Members turned on." },

    { key: "feed", label: "Release this as a podcast feed", kind: :checkbox,
      hint: "Publishes an RSS feed you can submit to Apple Podcasts, Spotify or any podcatcher. " \
            "Needs a title, synopsis and cover art." }
  ].freeze

  # Apple validates the feed's title, description and artwork on submission,
  # and won't take a feed missing any of them — so the checkbox asks for them
  # rather than publishing something that gets rejected later.
  FEED_REQUIRED_KEYS = %w[title synopsis cover].freeze

  # Global defaults at the top of music.yml — every release falls back to these.
  GLOBAL_FIELDS = [
    { key: "artist", label: "Artist", kind: :text, required: true,
      placeholder: "Your Name",
      hint: "The default artist for every release. Usually just you." },

    { key: "audience", label: "Audience", kind: :select, options: [ "free", "paid" ],
      hint: "The default for every release. Needs Members turned on to have any effect." }
  ].freeze

  RELEASE_KEYS = RELEASE_FIELDS.map { |f| f[:key] }.freeze
  GLOBAL_KEYS  = GLOBAL_FIELDS.map { |f| f[:key] }.freeze
  REQUIRED_RELEASE_KEYS = RELEASE_FIELDS.select { |f| f[:required] }.map { |f| f[:key] }.freeze

  # Audience is only meaningful with memberships configured — the same test
  # the post and page editors use before surfacing their own audience field.
  def self.release_fields(memberships: SiteFeature.memberships_enabled?)
    memberships ? RELEASE_FIELDS : RELEASE_FIELDS.reject { |f| f[:key] == "audience" }
  end

  def self.global_fields(memberships: SiteFeature.memberships_enabled?)
    memberships ? GLOBAL_FIELDS : GLOBAL_FIELDS.reject { |f| f[:key] == "audience" }
  end

  # A blank release, with every field present so the form draws an empty input
  # for each. Missing keys would render nothing at all; present-but-blank ones
  # show as prompts — the reason PodcastConfig seeds its full field set too.
  def self.blank_release
    RELEASE_KEYS.index_with { "" }
  end

  # What's missing before a release can be published as a feed. Empty means
  # it's ready. Used by the form to explain a refused checkbox.
  def self.feed_blockers(release)
    release = {} unless release.is_a?(Hash)
    FEED_REQUIRED_KEYS.reject { |k| release[k].to_s.strip.present? }
  end

  # Turn "Summer Release" into "summer-release" for the YAML key. Tracks point
  # at this, so it wants to be short and stable.
  def self.suggested_key(title, taken: [])
    base = title.to_s.parameterize.presence || "release"
    return base unless taken.include?(base)

    n = 2
    n += 1 while taken.include?("#{base}-#{n}")
    "#{base}-#{n}"
  end
end
