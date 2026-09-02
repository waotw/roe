# Single source of truth for the metadata fields the editor offers on posts,
# pages, and products.
#
# These definitions used to live as a hash literal inside
# app/views/shared/_metadata_editor.html.erb. They drove three things from
# there — the rendered field rows, the "+ Add Field" menu, and the JSON handed
# to the metadata_editor Stimulus controller — which made them invisible to
# every other part of the app. `release` and `track_number` were defined in
# Post::POST_TYPES but missing here, so choosing `post_type: music` surfaced
# neither; that class of drift is what this module exists to prevent.
#
# FIELD SHAPE mirrors the builder schemas (CollectionBuilderSchema,
# CardBuilderSchema, ActionBuilderSchema), with one difference kept on purpose
# for now: fields are a Hash keyed by field name rather than an Array of
# `key:` hashes, because ORDER IS LOAD-BEARING. The controller reads
# Object.keys() on this payload to order both the editor rows and the YAML it
# writes back, so a reordering here silently rewrites users' frontmatter.
#
# Per-post-type fields still live in Post::POST_TYPES; this module reads their
# `required:` flags through Post.required_fields_for_type. Merging the two is
# the next step, not this one.
module ContentMetadataSchema
  TYPES = %w[post page product].freeze

  def self.type?(type)
    TYPES.include?(type.to_s)
  end

  # The short list the NEW <thing> form asks for, beyond title/filename.
  # Posts vary by post_type and live in Post::POST_TYPES[:create_fields];
  # pages and products have no sub-types, so theirs are here.
  #
  # Keep these to what Roe needs to produce something that works: a product
  # can't be sold without a price and a SKU, and won't appear in a product
  # collection without an image. Everything else waits for the editor.
  CREATE_FIELDS = {
    "page"    => %w[subtitle].freeze,
    "product" => %w[category price sku image].freeze
  }.freeze

  # A schema entry (keyed by name) reshaped as a create-form field, matching the
  # shape of Post::POST_TYPES metadata_fields so one form partial renders either.
  def self.as_create_field(name, config)
    return nil unless config

    { name: name.to_s, type: config[:type], label: config[:label],
      hint: config[:hint], required: config[:required], options: config[:options] }
  end

  def self.create_fields_for(resource_type)
    schema = fields_for(resource_type)
    Array(CREATE_FIELDS[resource_type.to_s]).filter_map do |name|
      as_create_field(name, schema[name.to_s])
    end
  end

  # The known fields for a resource type, in display order.
  #
  # metadata: the item's parsed frontmatter. Needed because a few fields
  # resolve against the current values — the post's `post_type` decides which
  # media fields are required, and an imported post's `guid` hint differs.
  def self.fields_for(resource_type, metadata: {})
    metadata = {} unless metadata.is_a?(Hash)

    base = case resource_type.to_s
    when "post"    then post_fields(metadata)
    when "product" then product_fields
    else                pages_fields
    end

    # Each list carries a placeholder entry so this merge replaces it in place.
    # Hash#merge keeps an existing key's position, and that position is the
    # order the editor writes frontmatter in — appending would have shuffled
    # show_sidebar to the end of every file that has it on the next save, which
    # is a real content change and Site Sync drift nobody asked for.
    base.merge(sidebar_field(resource_type))
  end

  # The `show_sidebar` field, or nothing when there's no sidebar to talk about.
  #
  # Defaults to the opposite of what the scope already does, because that's the
  # only reason to add it: if the sidebar already covers pages, adding the field
  # to a page is how you turn it off; on a post it doesn't cover, adding it is
  # how you turn it on. Defaulting to the current behaviour would make the click
  # do nothing.
  def self.sidebar_field(resource_type)
    # Always defined, so a value already in a file renders as the checkbox it
    # is. Only *offered* in the Add Field menu when there's a sidebar to talk
    # about — a field that can't do anything shouldn't be on the menu, but a
    # value someone already set shouldn't degrade into a custom text field
    # because they later deleted their sidebar.
    unless Sidebar.exists?
      return {
        'show_sidebar' => {
          type: :checkbox, label: 'show_sidebar', available: false,
          hint: 'This site has no sidebar (site/layout/sidebar.md), so this setting does nothing.'
        }
      }
    end

    covered = Sidebar.covers?(resource_type)
    {
      'show_sidebar' => {
        type: :checkbox,
        label: 'show_sidebar',
        default: covered ? 'false' : 'true',
        # hint, not note: the ERB renders a checkbox's hint beside the box,
        # inside the label, which reads better than a line underneath — the
        # same treatment image_in_header and explicit already get. `note` is
        # for text fields, where there's no room alongside.
        hint: covered ?
          "The sidebar already shows here. Untick to hide it on this #{resource_type}." :
          "The sidebar doesn't show here. Tick to show it on this #{resource_type}."
      }
    }
  end

  def self.post_fields(metadata_hash)
    # Determine the current post_type so we can surface per-type required flags.
    current_post_type = (metadata_hash["post_type"].presence || "article").to_s
    type_required_names = Post.required_fields_for_type(current_post_type)
                              .map { |f| f[:name].to_s }
    required_for_type = ->(name) { type_required_names.include?(name.to_s) }

    {
      # Core fields
      'title' => { type: :text, label: 'title', required: true },
      'subtitle' => { type: :text, label: 'subtitle' },
      'date' => { type: :datetime, label: 'date', required: true },
      'post_type' => { type: :select, label: 'post_type', options: Post.post_type_options },
      'status' => { type: :select, label: 'status', options: ['draft', 'published', 'unlisted'], required: true },
      'author' => { type: :text, label: 'author', default_from_config: true },
      'tags' => { type: :text, label: 'tags', hint: 'arts, culture, …' },
      'collection' => { type: :text, label: 'collection', hint: 'Collection name(s), comma-separated (e.g. nav, footer)' },
      'url_name' => { type: :text, label: 'url_name', hint: 'auto-generated from title if blank' },
      'image' => { type: :text, label: 'image', hint: 'Post image, episode artwork, etc: /media/images/image-file.png', required: required_for_type.call('image') },
      'excerpt' => { type: :textarea, label: 'excerpt' },
      'audience' => {
        type: :select,
        label: 'audience',
        options: ['everyone', 'paid'],
        hint: 'Who should see/receive this post?',
        required: SiteFeature.memberships_enabled?
      },
      'published_to' => {
        type: :select,
        label: 'published_to',
        options: ['site', 'newsletter', 'both'],
        hint: 'Where should this be published?',
        required: SiteFeature.newsletters_enabled?
      },

      # Media fields — required flag comes from Post::POST_TYPES for the current type
      'audio' => { type: :text, label: 'audio', hint: "Example: /media/audio/audio-file.mp3", required: required_for_type.call('audio') },
      'video' => { type: :text, label: 'video', hint: "Example: /media/video/video-file.mp4", required: required_for_type.call('video') },
      'duration' => {
        type: :text,
        label: 'duration',
        hint: 'Auto-calculated from media file',
        readonly: true,
        required: required_for_type.call('duration')
      },
      'captions' => { type: :text, label: 'captions', hint: 'Path to captions file' },

      # Podcast-specific fields
      'podcast' => {
        type: :select,
        label: 'podcast',
        options: PodcastConfig.podcast_keys,
        required: required_for_type.call('podcast'),
        hint: 'Which podcast feed?'
      },
      'guid' => {
        type: :text,
        label: 'guid',
        # GUID is always read-only here. Either it was auto-generated by
        # Roe (and locked once published — podcast clients depend on
        # stability) or it came in from an importer (e.g. Substack) where
        # the original feed's GUID has to be preserved exactly to avoid
        # subscribers seeing every episode as new on the day of migration.
        readonly: true,
        hint: metadata_hash['substack_post_id'].present? ?
                'Imported from Substack feed — read-only to preserve subscriber dedup' :
                'Auto-generated UUID. Locked once the post is published.'
      },
      'explicit' => { type: :checkbox, label: 'explicit', hint: 'Explicit content?' },
      'episode_number' => { type: :text, label: 'episode_number', hint: 'Episode number' },
      'season' => { type: :text, label: 'season', hint: 'Season number' },
      'episode_type' => { type: :select, label: 'episode_type', options: ['full', 'trailer', 'bonus'], hint: 'Episode type' },

      # Music-specific fields. The release list comes from music.yml; the
      # release-link controller adds a link to that release's settings beside
      # this select, so the config is one click away from the track.
      'release' => {
        type: :select,
        label: 'release',
        required: required_for_type.call('release'),
        options: release_options(metadata_hash['release'])
      },
      'track_number' => {
        type: :text,
        label: 'track_number',
        required: required_for_type.call('track_number'),
        hint: 'Track number within the release'
      },
      # Credits and codes live with the track, not in music.yml — they describe
      # this recording, and nothing else shares them.
      'isrc' => {
        type: :text,
        label: 'isrc',
        hint: 'e.g. QMZ123456789 — the code for this recording'
      },
      'songwriters' => {
        type: :text,
        label: 'songwriters',
        hint: 'Legal names, comma-separated — not stage names'
      },
      'lyrics' => { type: :textarea, label: 'lyrics' },

      'show_sidebar' => { type: :checkbox, label: 'show_sidebar' },
      'image_in_header' => { type: :checkbox, label: 'image_in_header', hint: 'Show post image in the header?' },
      'related' => { type: :text, label: 'related', hint: 'Related item url_names, comma-separated (bi-directional)' }
    }
  end

  def self.product_fields
    {
      # Core product fields
      'title' => { type: :text, label: 'title', required: true },
      'category' => {
        type: :text,
        label: 'category',
        required: true,
        hint: begin
          categories = ProductCategory.all rescue []
          if categories.any?
            examples = categories.first(3).join(', ')
            "Add one: e.g., #{examples}"
          else
            'Add one: e.g., book, ebook, poster'
          end
        end
      },
      'url_name' => { type: :text, label: 'url_name', hint: 'auto-generated from title if blank' },
      'status' => { type: :select, label: 'status', options: ['draft', 'published'], required: true },
      'price' => { type: :text, label: 'price', required: true, hint: 'Price in dollars (e.g., 29.99)' },
      'sku' => { type: :text, label: 'sku', required: true, hint: 'Product SKU (required for publishing)' },
      'image' => { type: :text, label: 'image', required: true, hint: 'Product image: /media/images/product.jpg' },
      'description' => { type: :textarea, label: 'description', hint: 'Short description for Snipcart' },
      # A downloadable product. Turning this on reveals `file_guid` and drops
      # shipping from the cart. Snipcart has no API for digital goods — the
      # GUID is a copy-paste from their dashboard, so the editor links there.
      'digital' => {
        type: :checkbox,
        label: 'digital',
        hint: 'A digital file (e.g. mp3, ePub, PDF, etc.'
      },
      'file_guid' => {
        type: :text,
        label: 'file_guid',
        hint: 'The file GUID from your Snipcart dashboard'
      },
      # Snipcart requires weight in grams, as a whole number, and won't quote
      # postage without it. The unit sits after the input rather than in the
      # label: label width sets the whole column (longest label + 1 in the
      # metadata editor), so "weight (grams)" would have widened every row on
      # every product form to carry one field's unit.
      'weight' => {
        type: :text,
        label: 'weight',
        suffix: 'grams',
        hint: '500',
        note: 'Whole grams. Needed for Snipcart shipping rates — leave blank for digital products.'
      },
      'tags' => { type: :text, label: 'tags', hint: 'featured, sale, …' },
      'collection' => { type: :text, label: 'collection', hint: 'Collection name(s), comma-separated (e.g. featured)' },
      'show_sidebar' => { type: :checkbox, label: 'show_sidebar' },
      'group' => { type: :text, label: 'group', hint: 'Group ID for product variants (e.g., narnia-book-1)' },
      'variant' => { type: :text, label: 'variant', hint: 'Format: Paperback, Hardback, Ebook, etc.' },
      'primary' => { type: :checkbox, label: 'primary', hint: 'Only one product in a group should be checked as primary.' },
      'related' => { type: :text, label: 'related', hint: 'Related item url_names, comma-separated (bi-directional)' }
    }
  end

  def self.pages_fields
    {
      'title' => { type: :text, label: 'title', required: true },
      'subtitle' => { type: :text, label: 'subtitle' },
      'status' => { type: :select, label: 'status', options: ['draft', 'published', 'unlisted'], required: true },
      'tags' => { type: :text, label: 'tags', hint: 'arts, culture, …' },
      'collection' => { type: :text, label: 'collection', hint: 'Collection name(s), comma-separated (e.g. nav, footer)' },
      'url_name' => { type: :text, label: 'url_name', hint: 'auto-generated from title if blank' },
      'audience' => {
        type: :select,
        label: 'audience',
        options: ['everyone', 'paid'],
        hint: 'Who should see this page?',
        required: SiteFeature.memberships_enabled?
      },
      'image' => { type: :text, label: 'image', hint: 'Page image: /media/images/image-file.png' },
      'excerpt' => { type: :textarea, label: 'excerpt' },
      'show_sidebar' => { type: :checkbox, label: 'show_sidebar' },
      'related' => { type: :text, label: 'related', hint: 'Related item url_names, comma-separated (bi-directional)' }
    }
  end

  # Release keys from music.yml, plus whatever the track already names. A value
  # that isn't configured — an imported track, or one written before its release
  # existed — has to stay in the list, or opening the editor and saving would
  # silently clear it.
  def self.release_options(current)
    keys = begin
      ReleaseConfig.release_keys
    rescue StandardError
      []
    end
    current = current.to_s.strip
    return keys if current.blank? || keys.include?(current)
    keys + [ current ]
  end

  private_class_method :post_fields, :product_fields, :pages_fields
end
