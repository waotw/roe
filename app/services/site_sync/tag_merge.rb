module SiteSync
  # Combines the two sides' tag lists after a sync has moved the content.
  #
  # tags.yml isn't copied by Site Sync (Ledger::EXCLUDED_PATHS): each side
  # keeps it from its own content, so by the time this runs both lists already
  # hold every tag the content uses. What can still differ is tags nothing
  # uses — one created in MANAGE TAGS, or one deleted there.
  #
  # Two lists alone can't tell "created here" from "deleted there", so the
  # writing computer keeps the list both sides agreed at the last sync
  # (.tags-synced.json, also never copied). Against that:
  #   - on both sides            → kept
  #   - on one side, not before  → added there, kept
  #   - on one side, there before → deleted on the other side, dropped
  # Tags the content uses are always kept. With no record yet (the first sync
  # with this), everything on either side is kept.
  #
  # Runs only on the side that calls the peer. A live site on an older Roe
  # has no tags endpoint; the merge is skipped and the lists stay as they are.
  class TagMerge
    BASE_FILENAME = ".tags-synced.json"

    def self.run! = new.run!

    def self.merge(local, peer, base)
      local = TagList.clean(local)
      peer = TagList.clean(peer)
      return local | peer if base.nil?

      base = TagList.clean(base)
      both = local & peer
      only_one = (local | peer) - both
      both | only_one.reject { |tag| base.include?(tag) }
    end

    def run!
      return false unless Exchange.can_call_peer?

      peer = fetch
      return false if peer.nil?

      local = TagList.names
      merged = self.class.merge(local, peer, base) | TagList.used_names
      TagList.replace!(merged) unless same?(merged, local)
      return false unless same?(merged, peer) || send_to_peer(merged)

      save_base(TagList.names)
      true
    rescue => e
      Rails.logger.warn "[SiteSync::TagMerge] skipped: #{e.class} #{e.message}"
      false
    end

    def base
      path = base_path
      return nil unless File.exist?(path)

      Array(JSON.parse(File.read(path))["tags"])
    rescue JSON::ParserError
      nil
    end

    private

    def same?(a, b) = TagList.clean(a).sort == TagList.clean(b).sort

    def fetch
      response = call({})
      return nil unless response.is_a?(Net::HTTPSuccess)

      Array(JSON.parse(response.body)["tags"])
    end

    def send_to_peer(list)
      call({ set: TagList.clean(list) }).is_a?(Net::HTTPSuccess)
    end

    def call(body)
      uri = URI.parse(File.join(Exchange.peer_url, "/api/site_sync/tags"))
      Exchange.post_to_peer(uri, body.to_json)
    end

    def save_base(list)
      File.write(base_path, JSON.generate({ tags: TagList.clean(list).sort }))
    end

    def base_path = File.join(RoeSitePaths::SITE_PATH, BASE_FILENAME)
  end
end
