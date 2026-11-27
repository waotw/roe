# What a reference in a site's content points at: a link, a name, an address
# or a media file. The editor's Markdown check and the site-wide links check
# (LinkCheck) both ask here, so the two can't disagree about what's broken.
#
# Each answer is what the page itself does with the reference: a link that
# resolves here is a link on the page; one that doesn't shows as text, or
# the card or list item is left out.
module LinkTargets
  module_function

  # The callables MarkdownDoctor takes, all from here.
  def doctor_options
    {
      link_status: ->(target) { link_status(target) },
      name_matches: ->(name) { name_matches(name).map { |match| describe(match) } },
      address_status: ->(path) { address_status(path) },
      media_exists: ->(path) { media_exists?(path) }
    }
  end

  # `[[posts/x]]` and `[text](/posts/x.md)`.
  def link_status(target)
    InternalLinks.status(target)
  end

  # Everything a name could mean (a card's `post:`/`product:`, `order:`,
  # `related:`), the one Roe uses first. A name with a folder that finds
  # nothing there still finds the name anywhere, as a card does
  # (HasMarkdownExtensions#find_post_by_slug). A product group's name counts
  # too: a grouped collection lists the group in its products' place.
  def name_matches(name)
    found = ItemName.matches(name)
    parsed = ItemName.parse(name)
    found = ItemName.matches(parsed.name) if found.empty? && parsed.folder
    return found if found.any?

    group = ProductGroup.registry_names.find { |g| g.casecmp?(parsed.name.to_s) }
    group ? [ GroupName.new(group) ] : []
  end

  GroupName = Struct.new(:title)

  def describe(match)
    return "the product group “#{match.title}”" if match.is_a?(GroupName)

    "the #{match.class.model_name.human.downcase} “#{match.title}”"
  end

  # A link written as an address. Checked only when it's a post, page,
  # product or doc address; anything else (a feed, a tag page, the admin) is
  # :ok because there's nothing here to check it against. A redirect counts
  # as working: the link still arrives.
  #   [:ok, record|nil]  [:draft, record]  [:missing, nil]  [:moved, new_path]
  def address_status(path)
    path = path.to_s.split(/[?#]/, 2).first.to_s.chomp("/")
    return [ :ok, nil ] if path.empty? || redirected?(path)
    return old_store_status(path) if path.match?(%r{\A/store/[^/]+\z})

    params = route_params(path)
    record = params ? record_for(params) : :unchecked
    return [ :ok, nil ] if record == :unchecked
    return [ :missing, nil ] unless record

    [ record.published? ? :ok : :draft, record ]
  end

  # The params of the first route that answers a GET for `path`, or nil when
  # that route isn't a controller (a redirect like /signup → /sign-up).
  # recognize_path skips redirect routes and would hand /signup to the pages
  # catch-all, so the router is asked directly, in route order.
  def route_params(path)
    routes = Rails.application.routes
    routes.routes # draws them, when routes load lazily (a runner, a test)
    request = ActionDispatch::Request.new(Rack::MockRequest.env_for(path, method: "GET"))
    routes.router.recognize(request) do |route, params|
      app = route.app
      next if app.respond_to?(:matches?) && !app.matches?(request)

      return app.dispatcher? ? route.defaults.merge(params) : nil
    end
    nil
  rescue StandardError
    nil
  end

  def record_for(route)
    name = route[:url_name].to_s
    case [ route[:controller], route[:action] ]
    when %w[posts show]    then Post.all.find { |p| p.url_name == name }
    when %w[pages show]    then Page.all.find { |p| p.url_name == name }
    when %w[products show] then Product.where("json_extract(metadata, '$.url_name') = ?", name).first
    # A category's address answers while a published product is in it.
    when %w[products category] then StorePages.category_for_slug(route[:category]) ? :unchecked : nil
    when %w[documentation show]
      scope = route[:scope]
      docs = scope.present? ? Documentation.in_directory(scope) : Documentation.root
      docs.find { |d| d.url_name == name } || (BundledDocumentation.find(scope, name) if scope.present?)
    else :unchecked
    end
  end

  # Products and their categories were at /store/<name> before 0.5.1. The
  # address still answers (ProductsController#show), but the link should
  # say where the item lives now: :moved, with that address.
  def old_store_status(path)
    name = path.delete_prefix("/store/")
    product = Product.where("json_extract(metadata, '$.url_name') = ?", name).first
    return [ product.published? ? :moved : :draft, product.published? ? product.public_url : product ] if product

    category = StorePages.category_for_slug(name)
    return [ :moved, StorePages.category_url(category) ] if category

    # A product renamed since: /store/<old> goes on to /products/<old>, and
    # the rename's redirect from there.
    redirected?(Product.public_url_for(name)) ? [ :moved, Product.public_url_for(name) ] : [ :missing, nil ]
  end

  def redirected?(path)
    RedirectManager.rules.key?(path)
  end

  # A `/media/...` path: in one of the folders media is served from, or a
  # video whose original stays on the writing computer and plays from its
  # web versions (live).
  def media_exists?(path)
    MediaFiles.resolve(path).present? || VideoVariantGenerator.stand_in_file_for(path).present?
  end
end
