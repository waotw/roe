# Was a content file renamed, or removed while another was added? Used when
# Roe didn't make the change itself: the watcher, for edits outside Roe while
# it runs, and the sync at startup, for edits made while it was off.
#
# A wrong answer costs more than a missed one. A rename keeps the record (its
# id, newsletter sends) and moves every link to the old file onto the new one,
# so a wrong match points the site's links at a different post. A missed one
# only means the old record is removed and the new file starts fresh, and the
# Markdown check lists the links that broke. So a pair counts as a rename only
# when there's no doubt:
#
#   - the same folder (posts stay posts);
#   - the same text, exactly, and the same title — what a rename in Finder or
#     a text editor leaves untouched;
#   - one new file matches the old one, and no other old file matches it.
#
# A file renamed and edited before Roe saw it doesn't count.
module RenameMatch
  FOLDERS = %w[posts pages documentation products].freeze
  FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m

  module_function

  # `removed` maps each old path to its record; `added` lists new files that
  # have no record yet. Returns [renames, unsure]: renames maps old path to
  # new, and unsure lists the old paths that matched more than one way.
  def pairs(removed, added)
    matches = removed.to_h do |old_path, record|
      [ old_path, added.select { |file| folder(file) == folder(old_path) && same_file?(record, file) } ]
    end

    renames = {}
    unsure = []
    matches.each do |old_path, files|
      next if files.empty?

      if files.one? && matches.count { |_, others| others.include?(files.first) } == 1
        renames[old_path] = files.first
      else
        unsure << old_path
      end
    end
    [ renames, unsure ]
  end

  # Is `file` what `record` was synced from: the same body and title?
  def same_file?(record, file)
    body = record.content.to_s.strip
    title = record.metadata.to_h["title"].to_s.strip
    return false if body.empty? || title.empty? || !File.file?(file)

    match = File.read(file).match(FRONT_MATTER)
    return false unless match

    front = YAML.safe_load(match[1], permitted_classes: [ Date, Time, Symbol ])
    front.is_a?(Hash) && front["title"].to_s.strip == title && match[2].strip == body
  rescue StandardError
    false
  end

  # The content folder a path is in: "posts", "pages", … Works for absolute
  # paths and for the site-relative ones products store.
  def folder(path)
    FOLDERS.find { |name| path.to_s.include?("/#{name}/") || path.to_s.start_with?("#{name}/") }
  end
end
