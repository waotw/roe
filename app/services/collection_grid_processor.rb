class CollectionGridProcessor
  def self.process(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Find all collection divs
    collections = doc.css(".collection")

    return doc.to_html if collections.empty?

    # Group consecutive collections
    groups = []
    current_group = []

    collections.each do |collection|
      if current_group.empty?
        # Start first group
        current_group << collection
      elsif collections_are_adjacent?(current_group.last, collection)
        # Add to current group
        current_group << collection
      else
        # Save current group if it has multiple collections
        groups << current_group if current_group.size > 1
        # Start new group
        current_group = [ collection ]
      end
    end

    # Don't forget last group
    groups << current_group if current_group.size > 1

    # Wrap each group in a grid
    groups.each do |group|
      wrap_in_grid(group)
    end

    doc.to_html
  end

  private

  def self.collections_are_adjacent?(prev_node, next_node)
    # Walk through siblings between prev and next
    # If we find any non-whitespace element, they're not adjacent
    current = prev_node.next_sibling

    while current && current != next_node
      # If it's an element (not text) or non-blank text, not adjacent
      if current.element?
        return false
      elsif current.text? && !current.text.strip.empty?
        return false
      end
      current = current.next_sibling
    end

    true
  end

  def self.wrap_in_grid(group)
    count = [ group.size, 3 ].min # Cap at 3 columns

    # Create wrapper div
    wrapper = Nokogiri::XML::Node.new("div", group.first.document)
    wrapper["class"] = "collection-grid collection-grid-#{count}"

    # Insert wrapper before first collection
    group.first.add_previous_sibling(wrapper)

    # Move all collections into wrapper
    group.each do |collection|
      wrapper.add_child(collection)
    end
  end
end
