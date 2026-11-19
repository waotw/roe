# Reads and rewrites the `tags:` entry in a content file's front matter,
# leaving every other line as it was. Bulk tag changes and the tag manager use
# this, so a rename shows in a diff as one changed line per file.
#
# Written in the form the metadata editor saves: tags: ["a", "b"].
module FrontMatterTags
  FRONT_MATTER = /\A(---[ \t]*\n)(.*?)(^---[ \t]*(?:\n|\z))/m
  # The `tags:` line and any indented or `- item` lines under it.
  ENTRY = /^tags:[^\n]*\n?(?:(?:[ \t]+[^\n]*|-[^\n]*)(?:\n|\z))*/

  module_function

  # The file's tags, or nil when it has no front matter to read.
  def read(text)
    match = text.to_s.match(FRONT_MATTER)
    return nil unless match

    data = YAML.safe_load(match[2], permitted_classes: [ Date, Time, Symbol ]) || {}
    return [] unless data.is_a?(Hash)

    case (value = data["tags"])
    when Array then value.map(&:to_s)
    when String then value.split(",").map(&:strip)
    else []
    end
  rescue Psych::Exception
    nil
  end

  # The file's text with its tags set to `tags`, or nil when the file has no
  # front matter or the result wouldn't read back as those tags.
  def replace(text, tags)
    text = text.to_s
    match = text.match(FRONT_MATTER)
    return nil unless match

    front = match[2]
    line = tags.empty? ? "tags: []\n" : "tags: [#{tags.map { |t| quote(t) }.join(', ')}]\n"

    front = if front.match?(ENTRY)
      front.sub(ENTRY, line)
    elsif tags.empty?
      front
    else
      front = "#{front}\n" unless front.empty? || front.end_with?("\n")
      front + line
    end

    result = "#{match[1]}#{front}#{match[3]}#{match.post_match}"
    read(result) == tags ? result : nil
  end

  # A double-quoted YAML string. JSON's escapes are valid YAML ones.
  def quote(tag)
    JSON.generate(tag.to_s, ascii_only: false)
  end
end
