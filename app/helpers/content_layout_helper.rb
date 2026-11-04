# Draws a record's content layout (ContentLayout): each part in order,
# groups as one <div>, a post's top parts inside <header class="post-header">.
#
# Each part is a partial in app/views/content_layouts/parts/. A name with no
# partial is shown as a metadata field when the record has a value for it,
# and skipped otherwise. A part the body already has is skipped (BodyCheck).
#
# The markup and classes match what the post-type templates drew before
# layouts, so themes keep working: .post-header, .post-header-top, .post-meta,
# .post-title, .podcast-episode and the rest.
module ContentLayoutHelper
  # A group holding one of these parts also gets the class the old post header
  # gave that row, so theme rules for .post-header-top and .post-meta apply.
  GROUP_CLASSES = {
    "post"    => { "title" => "post-header-top", "date" => "post-meta", "author" => "post-meta" },
    "product" => { "title" => "product-top" }
  }.freeze

  # Post types whose parts below the header sat inside a wrapper.
  POST_BELOW_HEADER_WRAPPERS = { "podcast" => "podcast-episode" }.freeze

  def render_content_layout(record, layout: ContentLayout.for(record), **locals)
    kind = layout_kind(record)
    context = layout_context(record, kind, layout, locals)
    body_check = ContentLayout::BodyCheck.new(record)

    rendered = layout.groups.map do |names|
      html = names.filter_map do |name|
        next if body_check.has?(name)
        part = render_layout_part(name, record, kind, context).to_s
        part.presence && { name: name, html: part }
      end
      { names: names, parts: html }
    end

    rendered.reject! { |group| group[:parts].empty? }
    kind == "post" ? wrap_post_layout(record, rendered) : safe_join(rendered.map { |g| layout_group_html(g, kind) }, "\n")
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

    {
      podcast_config: podcast_config,
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

  # A post's parts before the player and body go in <header class="post-header">,
  # the rest after it. A podcast's lower parts sit in .podcast-episode, as
  # before layouts.
  def wrap_post_layout(record, groups)
    split = groups.index { |g| (g[:names] & ContentLayout::BELOW_HEADER).any? } || groups.length
    top, rest = groups[0...split], groups[split..]

    out = []
    out << content_tag(:header, safe_join(top.map { |g| layout_group_html(g, "post") }, "\n"), class: "post-header") if top.any?
    lower = safe_join(rest.map { |g| layout_group_html(g, "post") }, "\n")
    wrapper = POST_BELOW_HEADER_WRAPPERS[record.post_type.to_s]
    out << (wrapper ? content_tag(:div, lower, class: wrapper) : lower) if rest.any?
    safe_join(out, "\n")
  end

  # One part on its own line is drawn as is; a group gets a <div>.
  def layout_group_html(group, kind)
    parts = group[:parts].map { |p| p[:html].html_safe }
    return parts.first if group[:names].length == 1

    classes = [ "layout-group" ]
    mapping = GROUP_CLASSES.fetch(kind, {})
    classes.concat(group[:names].filter_map { |name| mapping[name] }.uniq)
    content_tag(:div, safe_join(parts, "\n"), class: classes.join(" "))
  end

  # A part named after a metadata field the record has: its value, plainly.
  def render_layout_field(name, record, kind)
    value = record.respond_to?(:metadata) ? record.metadata[name] : nil
    value = value.join(", ") if value.is_a?(Array)
    return nil if value.blank? || value.is_a?(Hash)

    content_tag(:p, value.to_s, class: "#{kind}-field #{kind}-#{name.dasherize}")
  end
end
