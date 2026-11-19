require "test_helper"

class SiteSync::TagMergeTest < ActiveSupport::TestCase
  setup { @created = [] }
  teardown do
    @created.each { |f| File.delete(f) if File.exist?(f) }
    restore_peer
  end

  def make_post(name, tags)
    meta = { "title" => name, "url_name" => name, "status" => "draft",
             "post_type" => "article", "date" => "2024-01-01", "tags" => tags }
    slug = ContentWriter.new.write(kind: :post, filename: name, metadata: meta, body: "body")
    @created << File.join(RoeSitePaths::SITE_POSTS_PATH, "#{slug}.md")
  end

  # A live site holding `list`, answering /api/site_sync/tags the way the
  # real endpoint does. Returns what live ends up with.
  def fake_peer(list)
    @peer = list.dup
    @calls = []
    exchange = SiteSync::Exchange.singleton_class
    @saved = %i[can_call_peer? peer_url post_to_peer].to_h { |m| [ m, exchange.instance_method(m) ] }
    peer = self
    exchange.define_method(:can_call_peer?) { true }
    exchange.define_method(:peer_url) { "https://live.example" }
    exchange.define_method(:post_to_peer) do |_uri, body, **|
      peer.answer(JSON.parse(body))
    end
  end

  def answer(body)
    @calls << body
    @peer = body["set"] if body.key?("set")
    response = Net::HTTPOK.new("1.1", "200", "OK")
    json = { tags: @peer }.to_json
    response.define_singleton_method(:body) { json }
    response
  end

  def restore_peer
    return unless @saved

    exchange = SiteSync::Exchange.singleton_class
    @saved.each { |m, impl| exchange.define_method(m, impl) }
    @saved = nil
  end

  # ── The rule ─────────────────────────────────────────────────────────────

  test "with no record of the last sync, everything on either side is kept" do
    assert_equal %w[a b c], SiteSync::TagMerge.merge(%w[a b], %w[b c], nil).sort
  end

  test "a tag on one side only is kept if it's new, dropped if the other side deleted it" do
    base = %w[shared gone-live gone-local]
    local = %w[shared gone-live new-local]   # deleted gone-local, added new-local
    peer  = %w[shared gone-local new-live]   # deleted gone-live, added new-live

    assert_equal %w[new-live new-local shared], SiteSync::TagMerge.merge(local, peer, base).sort
  end

  # ── A sync ───────────────────────────────────────────────────────────────

  test "combines both lists, sends the result to live and remembers it" do
    TagList.replace!(%w[local-only])
    fake_peer(%w[live-only])

    assert SiteSync::TagMerge.run!
    assert_equal %w[live-only local-only], TagList.names.sort
    assert_equal %w[live-only local-only], @peer.sort
    assert_equal %w[live-only local-only], SiteSync::TagMerge.new.base
  end

  test "a tag deleted on one side since the last sync stays deleted" do
    TagList.replace!(%w[keep interviews])
    fake_peer(%w[keep interviews])
    SiteSync::TagMerge.run!

    TagList.replace!(%w[keep])           # deleted locally in MANAGE TAGS
    SiteSync::TagMerge.run!

    assert_equal %w[keep], TagList.names
    assert_equal %w[keep], @peer
  end

  test "tags the content uses are always kept" do
    make_post("tm-used", %w[tm-used])
    File.write(File.join(RoeSitePaths::SITE_PATH, ".tags-synced.json"), { tags: %w[tm-used] }.to_json)
    fake_peer([])

    SiteSync::TagMerge.run!
    assert_includes TagList.names, "tm-used"
  end

  test "nothing is sent when live already has the combined list" do
    TagList.replace!(%w[same])
    fake_peer(%w[same])

    SiteSync::TagMerge.run!
    assert_equal [ {} ], @calls, "only the read"
  end

  test "a live site without the tags endpoint is left alone" do
    TagList.replace!(%w[mine])
    fake_peer([])
    SiteSync::Exchange.singleton_class.define_method(:post_to_peer) { |*, **| Net::HTTPNotFound.new("1.1", "404", "Not Found") }

    assert_not SiteSync::TagMerge.run!
    assert_equal %w[mine], TagList.names
    assert_nil SiteSync::TagMerge.new.base
  end

  test "tags.yml and the record of the last sync never travel" do
    assert SiteSync::Ledger.excluded?("system/global/tags.yml")
    assert SiteSync::Ledger.excluded?(".tags-synced.json")
  end
end
