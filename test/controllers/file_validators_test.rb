require "test_helper"

# Every refresh used to download every image again: send_file responses had
# no ETag or Last-Modified, and Rack fell back to a bare "no-cache", so the
# browser's check had nothing to compare and always got the whole file.
class FileValidatorsTest < ActionDispatch::IntegrationTest
  IMAGE = "/media/images/validators-test.webp"
  AUDIO = "/media/audio/validators-test.mp3"

  setup do
    @written = []
  end

  teardown do
    @written.each { |path| FileUtils.rm_f(path) }
  end

  def write(path, content, mtime: nil)
    absolute = File.join(RoeSitePaths::SITE_PATH, path.delete_prefix("/"))
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, content)
    File.utime(mtime, mtime, absolute) if mtime
    @written << absolute
    absolute
  end

  def revalidate(path, etag: response.headers["ETag"], last_modified: response.headers["Last-Modified"], **headers)
    get path, headers: { "If-None-Match" => etag, "If-Modified-Since" => last_modified }.compact.merge(headers)
  end

  # ── Media ─────────────────────────────────────────────────────────────────

  test "media is sent with validators and must be checked before reuse" do
    write(IMAGE, "IMAGE BYTES")

    get IMAGE
    assert_response :success
    assert_equal "IMAGE BYTES", response.body
    assert_match(/\A"[0-9a-f]+"\z/, response.headers["ETag"], "a strong ETag, so If-Range can use it")
    assert response.headers["Last-Modified"].present?
    assert_equal "no-cache, public", response.headers["Cache-Control"]
  end

  test "an unchanged file answers 304 with no body" do
    write(IMAGE, "IMAGE BYTES")
    get IMAGE

    revalidate(IMAGE)
    assert_response :not_modified
    assert_empty response.body

    revalidate(IMAGE, last_modified: nil)
    assert_response :not_modified, "If-None-Match alone is enough"
  end

  test "a file replaced at the same size within the same second is sent again" do
    second = Time.at(1_800_000_000)
    write(IMAGE, "AAAA", mtime: second + 0.1)
    get IMAGE
    first_etag = response.headers["ETag"]

    write(IMAGE, "BBBB", mtime: second + 0.6)
    revalidate(IMAGE, etag: first_etag)
    assert_response :success
    assert_equal "BBBB", response.body
    refute_equal first_etag, response.headers["ETag"]
  end

  test "a file replaced at a new size is sent again" do
    write(IMAGE, "SHORT")
    get IMAGE
    first_etag = response.headers["ETag"]

    write(IMAGE, "MUCH LONGER CONTENT")
    revalidate(IMAGE, etag: first_etag)
    assert_response :success
    assert_equal "MUCH LONGER CONTENT", response.body
  end

  test "a range request still gets 206 and carries the validators" do
    write(AUDIO, "0123456789")

    get AUDIO, headers: { "Range" => "bytes=2-5" }
    assert_response :partial_content
    assert_equal "2345", response.body
    assert_equal "bytes 2-5/10", response.headers["Content-Range"]
    assert response.headers["ETag"].present?
  end

  test "If-Range that still matches gets the slice; a stale one gets the whole new file" do
    write(AUDIO, "0123456789")
    get AUDIO
    etag = response.headers["ETag"]

    get AUDIO, headers: { "Range" => "bytes=2-5", "If-Range" => etag }
    assert_response :partial_content
    assert_equal "2345", response.body

    write(AUDIO, "abcdefghij", mtime: Time.now + 5)
    get AUDIO, headers: { "Range" => "bytes=2-5", "If-Range" => etag }
    assert_response :success
    assert_equal "abcdefghij", response.body, "no slice that mixes old and new bytes"
  end

  test "a weak ETag in If-Range never gets a slice" do
    write(AUDIO, "0123456789")
    get AUDIO

    get AUDIO, headers: { "Range" => "bytes=2-5", "If-Range" => "W/#{response.headers["ETag"]}" }
    assert_response :success
    assert_equal "0123456789", response.body
  end

  # ── Paid media ────────────────────────────────────────────────────────────

  def paid_audio
    write(AUDIO, "PAID AUDIO")
    Medium.find_or_create_by!(file_path: AUDIO) { |m| m.media_type = "audio" }
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "validators-paid.md"),
      content: "Body.",
      metadata: { "title" => "Paid", "url_name" => "validators-paid", "status" => "published",
                  "audience" => "paid", "audio" => AUDIO }
    )
  end

  test "paid media is private, and a visitor who may not see it gets 403 even with a matching ETag" do
    paid_audio
    member = Member.create!(email: "paid@example.com", name: "Paid", tier: :paid, status: :active)
    member.update!(media_token: "validators-token") if member.media_token.blank?
    token = member.reload.media_token

    get "#{AUDIO}?token=#{token}"
    assert_response :success
    assert_equal "no-cache, private", response.headers["Cache-Control"]
    etag = response.headers["ETag"]

    get "#{AUDIO}?token=#{token}", headers: { "If-None-Match" => etag }
    assert_response :not_modified

    get AUDIO, headers: { "If-None-Match" => etag }
    assert_response :forbidden, "the check never skips the access check"
  end

  # ── Theme CSS, site JS, system images ─────────────────────────────────────

  test "site JS answers 304 when unchanged" do
    get "/javascript/search.js"
    assert_response :success
    assert_equal "no-cache, public", response.headers["Cache-Control"]

    revalidate("/javascript/search.js")
    assert_response :not_modified
  end

  test "theme CSS saved twice in one second is sent again" do
    path = File.join(RoeSitePaths::SITE_PATH, "theme", "validators-test.css")
    FileUtils.mkdir_p(File.dirname(path))
    @written << path
    second = Time.at(1_800_000_000)

    File.write(path, "a { color: red; }")
    File.utime(second + 0.1, second + 0.1, path)
    get "/theme/validators-test.css"
    assert_response :success
    first_etag = response.headers["ETag"]

    File.write(path, "a { color: blu; }")
    File.utime(second + 0.7, second + 0.7, path)
    revalidate("/theme/validators-test.css", etag: first_etag)
    assert_response :success
    assert_equal "a { color: blu; }", response.body
  end

  test "system images answer 304 when unchanged" do
    path = File.join(RoeSitePaths::SITE_PATH, "system", "assets", "images", "validators-test.png")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, "PNG")
    @written << path

    get "/system/images/validators-test.png"
    assert_response :success
    revalidate("/system/images/validators-test.png")
    assert_response :not_modified
  end
end
