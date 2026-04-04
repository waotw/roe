module AdminHelper
  def useful_links
    links = {}

    # Feed URLs
    links[:feeds] = {
      "RSS Feed" => feed_path,
      "Atom Feed" => feed_atom_path
    }

    # Published Pages - order by title in metadata JSON
    published_pages = Page.published.order(Arel.sql("json_extract(metadata, '$.title') ASC"))
    links[:pages] = published_pages.each_with_object({}) do |page, hash|
      hash[page.title || page.url_name] = "/#{page.url_name}"
    end

    # Member links (if members enabled)
    if members_enabled?
      links[:members] = build_member_links
    end

    # Common paths
    links[:other] = {
      "Home" => root_path,
      "Admin Dashboard" => admin_root_path
    }

    links
  end

  def build_member_links
    member_links = {}
    pages_path = Rails.root.join('site', 'pages')

    # Member page mappings
    member_pages = {
      'signup.md' => 'Sign Up',
      'signin.md' => 'Sign In'
    }

    member_pages.each do |filename, label|
      page = Page.find_by(file_path: pages_path.join(filename).to_s)
      member_links[label] = "/#{page.url_name}" if page
    end

    # Add upgrade if payments enabled
    if payments_enabled_with_stripe?
      upgrade_page = Page.find_by(file_path: pages_path.join('upgrade.md').to_s)
      member_links["Upgrade to Paid"] = "/#{upgrade_page.url_name}" if upgrade_page
    end

    member_links
  end

  private

  def payments_enabled_with_stripe?
    payments_config = SiteConfig.current('defaults/members')&.config&.dig('payments')
    return false unless payments_config && payments_config['enabled'] == true

    stripe_config = StripeConfig.current
    stripe_config.connected? && stripe_config.price_id.present?
  end
end
