module CollectionsHelper
  def item_path(item)
    case item
    when Post
      "/posts/#{item.url_name}"
    when Documentation
      "/documentation/#{item.url_name}"
    when Page
      "/#{item.url_name}"
    else
      "#"
    end
  end

  def pagination_params
    # Only include params that exist
    permitted = params.permit(:source, :order, :heading, :exclude).to_h.symbolize_keys
    permitted.reject { |k, v| v.blank? }
  end
end
