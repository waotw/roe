# Writes an extracted nav into a layout file — the header (inline links with
# `**|**` separators) or the sidebar (a bullet list). If the target already has
# content, it's backed up to <name>.replaced.md first so nothing is lost.
# Returns the path written.
class FilesImporter::NavWriter
  def self.write(links, target:)
    dir = LayoutFiles.dir
    FileUtils.mkdir_p(dir)

    path = target.to_s == "sidebar" ? File.join(dir, "sidebar.md") : LayoutFiles.path("header")
    markdown = target.to_s == "sidebar" ? sidebar_markdown(links) : header_markdown(links)

    if File.exist?(path) && File.read(path).strip.present?
      backup = File.join(dir, "#{File.basename(path, '.md')}.replaced.md")
      FileUtils.cp(path, backup)
    end

    File.write(path, markdown)
    path
  end

  def self.header_markdown(links)
    links.each_with_index.map do |l, i|
      separator = i < links.size - 1 ? " **|**" : ""
      "[#{l[:text]}](#{l[:href]})#{separator}"
    end.join("\n") + "\n"
  end

  def self.sidebar_markdown(links)
    "---\nposition: left\nscope: all\n---\n\n" +
      links.map { |l| "- [#{l[:text]}](#{l[:href]})" }.join("\n") + "\n"
  end
end
