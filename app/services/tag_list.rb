# The site's tags: the list in system/global/tags.yml, and the work of
# keeping it and the content that uses it in step.
#
# Its own file, written only by Roe, so it never tangles with settings. Site
# Sync doesn't copy it; SiteSync::TagMerge combines the two sides' lists after
# the content has moved.
#
# The list follows the content. TracksTags calls record_change after every
# post, page, product or doc save — from the admin, the file watcher, or a
# full sync — so a tag joins the list the first time something uses it and
# leaves when its last use goes. A tag added from MANAGE TAGS has no uses, so
# nothing removes it until it's deleted there.
#
# Roe's own docs (documentation/roe) are never counted and never changed.
#
# Tags are matched exactly, after trimming spaces. The public tag pages match
# case-insensitively, but the list keeps what was typed.
class TagList
  KINDS = %i[posts pages products docs].freeze

  # Top-level `tags:` and the lines that belong to it: indented lines, and the
  # `- item` lines of a block list written flush left.
  BLOCK = /^tags:[^\n]*\n?(?:(?:[ \t]+[^\n]*|-[^\n]*)\n?)*/

  LOCK_PATH = Rails.root.join("tmp", "tag_list.lock")

  class Error < StandardError; end

  class << self
    # ── The list ────────────────────────────────────────────────────────────

    def file = File.join(SiteConfig::SITE_PATH, "tags.yml")

    def names
      Array(read_config["tags"]).map { |t| t.to_s.strip }.reject(&:blank?).uniq
    end

    # The list for menus and suggestions: alphabetical, and the used tags when
    # the site has no list yet.
    def sorted_names
      sorted(listed? ? names : used_names)
    end

    # A site from before the list existed has no tags.yml. The first change or
    # the next full sync fills it from the content.
    def listed?
      read_config.key?("tags")
    end

    # Called by TracksTags with the difference one save made.
    def record_change(added:, removed:)
      added = clean(added)
      removed = clean(removed) - added
      return if added.empty? && removed.empty? && listed?

      locked do
        current = listed? ? names : used_names
        updated = current | added
        updated -= removed - used_names if removed.any?
        write(updated)
      end
    end

    # Adds every used tag the list is missing. Never removes: a tag created in
    # MANAGE TAGS is unused until something uses it. Runs after a full sync.
    def reconcile!
      locked { write(names | used_names) }
    end

    # Sets the whole list. Site Sync uses it after combining both sides.
    def replace!(list)
      locked { write(list) }
    end

    # Before 0.5.0 shipped, the list lived under `tags:` in content.yml. Moves
    # it to tags.yml, keeping anything already there, and takes it out of
    # content.yml. Runs on any read, so no save can miss it.
    def move_out_of_content_yml!
      path = SiteConfig::CONTENT_FILE
      return unless File.exist?(path)

      text = File.read(path)
      return unless text.match?(BLOCK)

      data = YAML.safe_load(text, permitted_classes: [ Date, Time, Symbol ])
      return unless data.is_a?(Hash) && data.key?("tags")

      locked do
        current = File.exist?(file) ? names_in_file : []
        write(current | clean(data["tags"]))
        SiteFile.write(path, text.sub(BLOCK, ""))
      end
    rescue Psych::Exception
      nil
    end

    def add!(name)
      name = validate!(name)
      raise Error, "#{name} is already a tag." if names.include?(name)

      locked { write(names | [ name ]) }
      name
    end

    # ── Usage ───────────────────────────────────────────────────────────────

    # { "lab" => { posts: 10, pages: 0, products: 5, docs: 0 }, ... } for every
    # tag on the list or in use.
    def usage
      counts = Hash.new { |h, k| h[k] = KINDS.index_with { 0 } }
      each_record { |kind, record| clean(record.tags).each { |tag| counts[tag][kind] += 1 } }
      names.each { |name| counts[name] }
      counts.sort_by { |name, _| name.downcase }.to_h
    end

    # For the metadata editor's tags dropdown: [{ name:, count: }],
    # alphabetical. Spellings that differ only in case sit together, the most
    # used first, so the dropdown steers toward it.
    def field_options
      usage.map { |name, counts| { name: name, count: counts.values.sum } }
           .sort_by { |o| [ o[:name].downcase, -o[:count], o[:name] ] }
    end

    def used_names
      tags = []
      each_record { |_kind, record| tags.concat(clean(record.tags)) }
      tags.uniq
    end

    def records_with(name)
      found = []
      each_record { |_kind, record| found << record if clean(record.tags).include?(name) }
      found
    end

    def show_products? = SiteFeature.store_enabled?

    # Docs of the site's own, not Roe's.
    def show_docs?
      Documentation.select(:id, :file_path).any? { |doc| tracked?(doc) }
    end

    def tracked?(record)
      return true unless record.is_a?(Documentation)

      record.url_scope != "roe"
    end

    # ── Changing content ───────────────────────────────────────────────────

    # Renames a tag everywhere. Renaming onto a tag that already exists merges
    # the two; an item that had both keeps one. Returns the number of files
    # changed.
    def rename!(from, to)
      from = from.to_s.strip
      to = validate!(to)
      raise Error, "#{from} isn't a tag." unless names.include?(from) || used_names.include?(from)
      return 0 if from == to

      changed = records_with(from).count { |record| retag(record, add: [ to ], remove: [ from ]) }
      locked { write((names - [ from ]) | [ to ]) }
      changed
    end

    # Removes a tag from every file that has it, then from the list.
    def delete!(name)
      name = name.to_s.strip
      changed = records_with(name).count { |record| retag(record, remove: [ name ]) }
      locked { write(names - [ name ]) }
      changed
    end

    # Adds and removes tags on one item's file, then re-reads the file so the
    # record (and, through TracksTags, the list) follow. Returns true when the
    # file changed.
    def retag(record, add: [], remove: [])
      return false unless tracked?(record)

      path = content_path(record)
      return false unless File.exist?(path)

      text = File.read(path)
      current = clean(tags_in(text) || [])
      updated = (current - clean(remove)) | clean(add)
      return false if updated == current

      rewritten = FrontMatterTags.replace(text, updated)
      return false unless rewritten && SiteFile.write(path, rewritten)

      resync(record, path)
      true
    end

    # ── tags.yml ────────────────────────────────────────────────────────────

    # The text with its `tags:` block set to `list`, in place if there is one,
    # else at the end. Anything else in the text is kept as written.
    def with_list(text, list)
      block = "tags:#{list.empty? ? ' []' : ''}\n" + list.map { |t| "  - #{yaml_scalar(t)}\n" }.join
      text = text.to_s
      if text.match?(BLOCK)
        text.sub(BLOCK, block)
      else
        text = "#{text}\n" unless text.empty? || text.end_with?("\n")
        text + block
      end
    end

    def clean(tags)
      Array(tags).map { |t| t.to_s.strip }.reject(&:blank?).uniq
    end

    private

    def write(list)
      FileUtils.mkdir_p(File.dirname(file))
      SiteFile.write(file, with_list("", sorted(list)))
    end

    def sorted(list) = clean(list).sort_by { |t| [ t.downcase, t ] }

    def read_config
      move_out_of_content_yml!
      return {} unless File.exist?(file)

      data = YAML.safe_load(File.read(file), permitted_classes: [ Date, Time, Symbol ])
      data.is_a?(Hash) ? data : {}
    rescue Psych::Exception
      {}
    end

    # Without the move, for use inside it.
    def names_in_file
      data = YAML.safe_load(File.read(file), permitted_classes: [ Date, Time, Symbol ])
      clean(data.is_a?(Hash) ? data["tags"] : [])
    rescue Psych::Exception
      []
    end

    def validate!(name)
      name = name.to_s.strip
      raise Error, "A tag needs a name." if name.empty?
      raise Error, "A tag can't contain a comma." if name.include?(",")

      name
    end

    # Plain where YAML reads it back unchanged, quoted otherwise.
    def yaml_scalar(tag)
      plain = tag.match?(/\A[[:alnum:]][[:alnum:] _.\/-]*\z/) &&
              !tag.match?(/\A[-+]?[\d._]+\z/) &&
              !%w[true false yes no on off null y n].include?(tag.downcase)
      plain ? tag : tag.to_json
    end

    def each_record
      { posts: Post, pages: Page, products: Product, docs: Documentation }.each do |kind, model|
        model.select(:id, :metadata, :file_path).find_each do |record|
          yield kind, record if tracked?(record)
        end
      end
    end

    def tags_in(text)
      FrontMatterTags.read(text)
    end

    def content_path(record)
      path = record.file_path.to_s
      path.start_with?("/") ? path : File.join(RoeSitePaths::SITE_PATH, path)
    end

    def resync(record, path)
      if record.is_a?(Documentation)
        Documentation.create_or_update_from_file(path)
      else
        ContentSync.sync_file(path)
      end
    end

    # One writer at a time, across threads and processes. Re-entrant, since a
    # second flock on a new handle in the same process would wait forever.
    def locked
      return yield if Thread.current[:tag_list_locked]

      FileUtils.mkdir_p(File.dirname(LOCK_PATH))
      File.open(LOCK_PATH, File::RDWR | File::CREAT) do |f|
        f.flock(File::LOCK_EX)
        Thread.current[:tag_list_locked] = true
        yield
      ensure
        Thread.current[:tag_list_locked] = false
      end
    end
  end
end
