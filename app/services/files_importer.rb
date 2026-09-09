# Imports a ZIP/folder of markdown + HTML into Roe as draft posts and pages.
# A source adapter in the same family as FeedImporter: it parses each file into
# a normalized Document, classifies it as a post or page, maps it to Roe
# frontmatter, and writes it through the shared ContentWriter. Bundled media
# handling and the review UI build on top of this core.
module FilesImporter
  # One source file, normalized to the fields the classifier, mapper, and
  # writer need. `custom` carries any frontmatter Roe doesn't map, passed
  # through verbatim so nothing is lost.
  Document = Struct.new(
    :source_path,  # path relative to the import root, e.g. "blog/2024/hi.md"
    :format,       # :markdown | :html
    :basename,     # filename without extension, preserved as the Roe filename
    :title,
    :slug,         # explicit slug/permalink from the source, else nil
    :date,         # raw date string (frontmatter, Jekyll filename, or <meta>)
    :tags,
    :author,
    :subtitle,
    :excerpt,
    :body,         # markdown
    :custom,       # leftover frontmatter (Hash), passed through as custom fields
    :type_hint,    # "post" | "page" | nil (from frontmatter layout/type)
    :dated,        # true when a real publish date is known
    :episode_like, # looks like a podcast episode (has audio) → suggest Feed Imports
    :kind,         # :post | :page | :ambiguous (filled by Classifier)
    keyword_init: true
  )
end
