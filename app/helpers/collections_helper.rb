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

  def collection_tag_path(tag)
    "/collections/#{tag.parameterize}"
  end

  def collection_type_path(type)
    "/collections/type-#{type.parameterize}"
  end

  def collection_exists?(slug)
    # This could be expanded to check manifest or actual pages
    true # For now, assume all collections are valid
  end
end
