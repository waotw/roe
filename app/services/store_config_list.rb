# frozen_string_literal: true

# Read / surgically-replace a list-valued key in system/features/store.yml
# without reformatting the rest of the file (comments, quote styles, and every
# other key stay byte-identical — round-tripping through YAML.load + to_yaml
# would rewrite the whole file in Psych's preferred style).
#
# Generalizes the block-replacement logic ProductCategory uses so other
# registries (product groups, …) can share it. Dedup is case-insensitive; the
# value is stored stripped but with its original case preserved (group names
# are user-facing labels, so we don't lowercase them the way categories do).
class StoreConfigList
  STORE_PATH = -> { File.join(RoeSitePaths::SITE_PATH, "system/features/store.yml") }

  # Read from the file, not from SiteConfig.
  #
  # `write` edits store.yml directly, so reading the database asks a different
  # source than the one being written — and the two diverge exactly when it
  # matters. After a sync brings in a new store.yml, ContentSync refreshes
  # site.yml only, so the database still holds the pre-sync list while the file
  # holds the new one. A product saving then judges its category against the
  # stale list and rewrites the file from it, which both drops whatever the
  # sync brought in and leaves store.yml modified moments after the ledger was
  # written — the drift that shows up right after a sync that worked.
  #
  # It also breaks within a single run: two products saving in a row both read
  # the same stale list, so the second one's write drops the first one's value.
  #
  # SiteConfig is the fallback for a missing or unparseable file, since a
  # slightly stale list beats none at all for the editor's autocomplete.
  def self.all(key)
    value = file_value(key) || SiteConfig.feature("store", key) || []
    value.is_a?(String) ? value.split(",").map(&:strip).reject(&:blank?) : value
  end

  def self.file_value(key)
    path = STORE_PATH.call
    return nil unless File.exist?(path)

    (YAML.load_file(path) || {})[key]
  rescue Psych::SyntaxError, Errno::EACCES => e
    Rails.logger.warn "[StoreConfigList] Couldn't read #{key} from store.yml: #{e.message}"
    nil
  end

  # Add a value if not already present (case-insensitively). No-op on blank or
  # duplicate. Returns false on a write error (non-critical, logged).
  def self.add(key, value)
    stored = value.to_s.strip
    list = all(key)
    return if stored.blank? || list.any? { |v| v.to_s.casecmp?(stored) }

    write(key, (list + [ stored ]).sort_by { |v| v.to_s.downcase })
  end

  def self.write(key, list)
    File.write(STORE_PATH.call, rewritten(STORE_PATH.call, key, list))
  rescue Errno::ENOENT, Errno::EACCES => e
    Rails.logger.error "[StoreConfigList] Failed to update #{key}: #{e.message}"
    false
  rescue Psych::SyntaxError => e
    Rails.logger.error "[StoreConfigList] Invalid YAML in store.yml: #{e.message}"
    false
  end

  # Replace just the `<key>:` block. Handles a bare header with `- item`
  # children, an inline `[a, b]`/scalar form, and a missing key (appended).
  def self.rewritten(path, key, list)
    block = yaml_block(key, list)
    return block unless File.exist?(path)

    header = /\A#{Regexp.escape(key)}:\s*\Z/
    inline = /\A#{Regexp.escape(key)}:\s*(\[.*\]|\S.*)\Z/
    in_block = false
    found = false
    out = []

    File.read(path).each_line do |line|
      if !in_block && line.match?(header)
        found = true
        in_block = true
        out << block
        next
      end
      if !in_block && line.match?(inline)
        found = true
        out << block
        next
      end
      if in_block
        # A `- item` — indented OR at column 0, since a block sequence may sit
        # at the parent key's indent and that's valid YAML — or a blank line:
        # still inside the block, so skip it, we've already emitted the
        # replacement. Requiring indentation here missed column-0 items and
        # left them behind, producing a second, stale list and a file that no
        # longer parses. ProductCategory's copy was fixed for this; this one,
        # written to generalize it, kept the original bug.
        next if line.match?(/\A[ \t]*-\s/) || line.match?(/\A[ \t]*\Z/)

        in_block = false
      end
      out << line
    end

    result = out.join
    found ? result : "#{result.chomp}\n\n#{block}"
  end

  def self.yaml_block(key, list)
    items = Array(list).compact.map(&:to_s).reject(&:empty?)
    return "#{key}: []\n" if items.empty?

    lines = [ "#{key}:" ]
    items.each { |v| lines << %(  - "#{v.gsub('\\', '\\\\').gsub('"', '\\"')}") }
    "#{lines.join("\n")}\n"
  end
end
