module ProductsHelper
  # Render a product's body and add theme-targetable hooks WITHOUT any markup
  # syntax in the author's markdown — the body stays pure Markdown, and the
  # system classes the predictable elements of a product page by convention:
  #
  #   * first heading            -> class `product-title`
  #   * first image or gallery   -> class `product-image` (on the <img>, or on
  #                                 the gallery wrapper when it's a gallery)
  #   * everything before the
  #     first `---`              -> wrapped in <div class="product-top">; the
  #                                 `---` (an <hr>) is KEPT as a visible divider.
  #                                 Float the image + details inside .product-top
  #                                 and give it `display: flow-root` (or flex)
  #                                 to contain the floats — no `{: .clear-floats}`.
  #                                 Hide the rule with `hr { display: none }` if
  #                                 you don't want it shown.
  #
  # Position-based, so it only fires on a product's predictable shape (documented
  # as a convention). Runs for dynamic AND static, since both render products/show.
  def product_content(product)
    frag = Nokogiri::HTML::DocumentFragment.parse(product.to_html(preview: editor_preview?).to_s)

    if (title = frag.at_css("h1"))
      add_html_class(title, "product-title")
    end

    if (hero = first_product_hero(frag))
      add_html_class(hero, "product-image")
    end

    wrap_product_top(frag)

    frag.to_html.html_safe
  end

  private

  # First image-bearing element in document order: a gallery wrapper (captioned
  # <figure class="gallery-figure"> or a bare <div class="gallery">), or a
  # standalone <img> that isn't inside a gallery.
  def first_product_hero(frag)
    frag.css("figure.gallery-figure, div.gallery, img").find do |node|
      case node.name
      when "figure" then true
      when "div"    then node.ancestors("figure.gallery-figure").empty?
      when "img"    then node.ancestors("figure.gallery-figure, div.gallery").empty?
      end
    end
  end

  # Wrap every top-level node before the first `---` (thematic break) in
  # .product-top. The `---` (rendered as an <hr>) is LEFT in place: it still
  # shows as a divider for authors who don't know about this convention, and a
  # theme that wants .product-top without the rule can `hr { display: none }`.
  # No `---` in the body => no wrapper (opt-in), so products that don't need it
  # are untouched.
  def wrap_product_top(frag)
    hr = frag.children.find { |node| node.name == "hr" }
    return unless hr

    top = Nokogiri::XML::Node.new("div", frag.document)
    top["class"] = "product-top"

    frag.children.take_while { |node| node != hr }.each { |node| top.add_child(node) }
    hr.add_previous_sibling(top)
  end

  def add_html_class(node, klass)
    node["class"] = (node["class"].to_s.split + [ klass ]).uniq.join(" ")
  end
end
