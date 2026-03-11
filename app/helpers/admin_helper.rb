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

    # Common paths
    links[:other] = {
      "Home" => root_path,
      "Admin Dashboard" => admin_root_path
    }

    links
  end
end
