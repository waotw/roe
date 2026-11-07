# Draws a record's content layout (ContentLayout): its blocks in order, each
# as the element its place gives it.
#
#   header   <header class="…">   the first block before the content
#   group    <div class="…">      blocks between header, content and footer
#   content  the writing and the boxes grouped with it; wrapped in a
#            <div class="…"> only when the block is named
#   footer   <footer class="…">   the last block after the content
#
# A block or row gets the classes written in the layout; without any, a
# group is .layout-group and a row of several boxes .layout-row. A row of one
# box with no classes is the part alone. Roe's default layouts write out the
# classes themes already use (.post-header, .post-header-top, .post-meta,
# .podcast-episode, .product-top), so they draw what the post-type templates
# did — and an edited layout draws only what it says.
#
# Each part is a partial in app/views/content_layouts/parts/. A name with no
# partial is shown as a metadata field when the record has a value for it,
# and skipped otherwise. A part the body already has is skipped (BodyCheck).
# Blocks and rows left with nothing to show are dropped.
module ContentLayoutHelper
  def render_content_layout(record, layout: ContentLayout.for(record), **locals)
    kind = layout_kind(record)
    context = layout_context(record, kind, layout, locals)
    body_check = ContentLayout::BodyCheck.new(record)

    blocks = layout.blocks.filter_map do |block|
      rows = block.rows.filter_map do |row|
        parts = row.parts.filter_map do |name|
          next if body_check.has?(name)
          render_layout_part(name, record, kind, context).to_s.presence&.html_safe
        end
        layout_row_html(row, parts) if parts.any?
      end
      layout_block_html(block, rows) if rows.any?
    end
    safe_join(blocks, "\n")
  end

  # Partials are rendered by name only from the fixed list, so a layout file
  # can't reach any other template.
  def render_layout_part(name, record, kind, context)
    if ContentLayout::BUILT_PARTS.include?(name)
      render(partial: "content_layouts/parts/#{name}", locals: { record: record, kind: kind, context: context })
    else
      render_layout_field(name, record, kind)
    end
  end

  private

  def layout_kind(record)
    case record
    when Post          then "post"
    when Page          then "page"
    when Product       then "product"
    when Documentation then "documentation"
    else "post"
    end
  end

  # What several parts need, worked out once per page: the record's podcast
  # (posts and pages) and, for an episode, the show's other episodes.
  def layout_context(record, kind, layout, locals)
    podcast_key = record.respond_to?(:metadata) ? record.metadata["podcast"].to_s.presence : nil
    episode = kind == "post" && record.post_type == "podcast" && podcast_key
    podcast_config =
      if kind == "page"
        (podcast_enabled? && podcast_key) ? PodcastConfig.get(podcast_key) : nil
      elsif episode
        PodcastConfig.get(podcast_key)
      end

    release_key = kind == "page" ? record.metadata["release"].to_s.strip.presence : nil
    release_config = release_key && SiteFeature.music_enabled? ? ReleaseConfig.get(release_key) : nil

    {
      podcast_config: podcast_config,
      release_config: release_config,
      podcast_episodes: episode ? podcast_episodes_for(podcast_key) : nil,
      layout_parts: layout.parts
    }.merge(locals)
  end

  # Newest first, the order the episode list and ⏮ ⏭ use.
  def podcast_episodes_for(podcast_key)
    Post.published
        .where("json_extract(metadata, '$.post_type') = ?", "podcast")
        .where("json_extract(metadata, '$.podcast') = ?", podcast_key)
        .order(Arel.sql("json_extract(metadata, '$.date') DESC"))
        .to_a
  end

  def layout_block_html(block, rows)
    inner = safe_join(rows, "\n")
    css = block.classes.join(" ").presence
    case block.role
    when :header  then content_tag(:header, inner, class: css)
    when :footer  then content_tag(:footer, inner, class: css)
    when :content then css ? content_tag(:div, inner, class: css) : inner
    else               content_tag(:div, inner, class: css || "layout-group")
    end
  end

  def layout_row_html(row, parts)
    return parts.first if row.parts.length == 1 && row.classes.empty?

    content_tag(:div, safe_join(parts, "\n"), class: row.classes.join(" ").presence || "layout-row")
  end

  # A part named after a metadata field the record has: its value, plainly.
  def render_layout_field(name, record, kind)
    value = record.respond_to?(:metadata) ? record.metadata[name] : nil
    value = value.join(", ") if value.is_a?(Array)
    return nil if value.blank? || value.is_a?(Hash)

    content_tag(:p, value.to_s, class: "#{kind}-field #{kind}-#{name.dasherize}")
  end
end
