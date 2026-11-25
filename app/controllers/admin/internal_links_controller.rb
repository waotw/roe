# The list the editor offers when a link to another post, page, product or
# doc is being written: after `](/` in a Markdown link, after `[[` in a
# wikilink, and on clicking an existing link. Fetched once per editor page.
# See InternalLinks.
class Admin::InternalLinksController < Admin::BaseController
  # GET /admin/internal_links
  # → { items: [{ title:, ref:, url_name:, address:, draft:, updated: }] }
  def index
    render json: { items: InternalLinks.listing }
  end
end
