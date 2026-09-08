# frozen_string_literal: true

require "test_helper"

# Anything under site/media used to be served to anyone who knew the path —
# MediaController skipped authentication and had no audience check, so a paid
# post's audio was a public download. The feed didn't hand the URL out, but
# that's obscurity, not access control.
class ProtectedMediaTest < ActionDispatch::IntegrationTest
  AUDIO = "/media/audio/track.mp3"

  def write_file(path = AUDIO)
    absolute = File.join(RoeSitePaths::SITE_PATH, path.delete_prefix("/"))
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "AUDIO BYTES")
    Medium.find_or_create_by!(file_path: path) { |m| m.media_type = "audio" }
  end

  def post_referencing(audience:, path: AUDIO, status: "published")
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "p#{Post.count}.md"),
      content: "Body.",
      metadata: { "title" => "P#{Post.count}", "url_name" => "p#{Post.count}",
                  "status" => status, "audience" => audience, "audio" => path }
    )
  end

  # Referenced from the BODY. The image field is deliberately not used here:
  # a featured image is public by design (rendered above the paywall and
  # published as og:image), so it can't stand in for protected media.
  def page_referencing(audience:, path: AUDIO)
    Page.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "pages", "pg#{Page.count}.md"),
      content: "Body. ![a](#{path})",
      metadata: { "title" => "Pg#{Page.count}", "url_name" => "pg#{Page.count}",
                  "status" => "published", "audience" => audience }
    )
  end

  def member(tier: :paid, status: :active)
    Member.create!(email: "m#{Member.count}@example.com", name: "M#{Member.count}",
                   tier: tier, status: status)
  end

  # ── The hole ───────────────────────────────────────────────────────────────

  test "a paid post's audio is not served to the public" do
    write_file
    post_referencing(audience: "paid")

    get AUDIO
    assert_response :forbidden
  end

  test "a paid page's body media is not served to the public" do
    write_file
    page_referencing(audience: "paid")

    get AUDIO
    assert_response :forbidden
  end

  # ── What a paid record still shows everyone ────────────────────────────────

  # Rendered in the header above the paywall, and published by Roe as og:image
  # and in collection listings. Returning 403 for a URL Roe advertises isn't
  # protection — it's a broken page and a broken social card.
  test "a paid post's featured image is public" do
    image = "/media/images/hero.jpg"
    Medium.find_or_create_by!(file_path: image) { |m| m.media_type = "images" }
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, "media", "images"))
    File.write(File.join(RoeSitePaths::SITE_PATH, "media", "images", "hero.jpg"), "IMG")
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "hero-post.md"),
      content: "Body.",
      metadata: { "title" => "Hero", "url_name" => "hero-post", "status" => "published",
                  "audience" => "paid", "image" => image }
    )

    get image
    assert_response :success
  end

  # audience is a cached column, so sites that ran the old rule have images
  # sitting at "paid" that should now be public. Nothing recomputes them on
  # their own, so a deploy alone would leave the 403 in place.
  test "a boot recompute frees a featured image marked paid under the old rule" do
    image = "/media/images/stale.jpg"
    medium = Medium.find_or_create_by!(file_path: image) { |m| m.media_type = "images" }
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, "media", "images"))
    File.write(File.join(RoeSitePaths::SITE_PATH, "media", "images", "stale.jpg"), "IMG")
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "stale-post.md"),
      content: "Body.",
      metadata: { "title" => "Stale", "url_name" => "stale-post", "status" => "published",
                  "audience" => "paid", "image" => image }
    )
    medium.update_column(:audience, "paid") # the state an existing site is in

    get image
    assert_response :forbidden, "precondition — the stale row is what returns 403"

    Medium.recompute_paid!

    assert_equal "free", medium.reload.audience
    get image
    assert_response :success, "a deploy left the image unreachable"
  end

  # Only paid rows can be stale — every rule moves files toward public — so the
  # recompute visits a handful rather than the whole library.
  test "the recompute leaves genuinely paid media alone" do
    write_file
    post_referencing(audience: "paid")
    medium = Medium.find_by(file_path: AUDIO)
    assert_equal "paid", medium.audience

    Medium.recompute_paid!

    assert_equal "paid", medium.reload.audience, "the recompute unprotected real paid media"
  end

  # Moving the paywall changes which side a file is on without changing which
  # files are referenced, so the recompute has to re-ask rather than diff the
  # reference list.
  test "moving the paywall down frees the media it reveals" do
    write_file
    post = Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "moving.md"),
      content: "Intro\n\n```form\nfor: paid_content\n```\n\nGated ![a](#{AUDIO})",
      metadata: { "title" => "Moving", "url_name" => "moving", "status" => "published",
                  "audience" => "paid" }
    )
    assert_equal "paid", Medium.find_by(file_path: AUDIO).audience

    # Same file, same reference — only the gate moved.
    post.update!(content: "Intro ![a](#{AUDIO})\n\n```form\nfor: paid_content\n```\n\nGated text")

    assert_equal "free", Medium.find_by(file_path: AUDIO).audience,
      "the file is above the paywall now and still isn't being served"
    get AUDIO
    assert_response :success
  end

  test "moving the paywall up protects the media it hides" do
    write_file
    post = Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "moving2.md"),
      content: "Intro ![a](#{AUDIO})\n\n```form\nfor: paid_content\n```\n\nGated text",
      metadata: { "title" => "Moving2", "url_name" => "moving2", "status" => "published",
                  "audience" => "paid" }
    )
    assert_equal "free", Medium.find_by(file_path: AUDIO).audience

    post.update!(content: "Intro\n\n```form\nfor: paid_content\n```\n\nGated ![a](#{AUDIO})")

    assert_equal "paid", Medium.find_by(file_path: AUDIO).audience,
      "the file moved behind the paywall and is still public"
  end

  # A free video above the gate with the article paid after it is a normal
  # shape, and the point of choosing where the block goes.
  test "media above the paywall is public even on a paid post" do
    free = "/media/images/preview.jpg"
    Medium.find_or_create_by!(file_path: free) { |m| m.media_type = "images" }
    FileUtils.mkdir_p(File.join(RoeSitePaths::SITE_PATH, "media", "images"))
    File.write(File.join(RoeSitePaths::SITE_PATH, "media", "images", "preview.jpg"), "IMG")
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "gated.md"),
      content: "Free ![p](#{free})\n\n```form\nfor: paid_content\n```\n\nPaid ![a](#{AUDIO})",
      metadata: { "title" => "Gated", "url_name" => "gated", "status" => "published",
                  "audience" => "paid" }
    )

    get free
    assert_response :success
  end

  # The other half of the same post: below the gate stays shut.
  test "media below the paywall is still protected" do
    write_file
    Post.create!(
      file_path: File.join(RoeSitePaths::SITE_PATH, "posts", "gated2.md"),
      content: "Free intro\n\n```form\nfor: paid_content\n```\n\nPaid ![a](#{AUDIO})",
      metadata: { "title" => "Gated2", "url_name" => "gated2", "status" => "published",
                  "audience" => "paid" }
    )

    get AUDIO
    assert_response :forbidden
  end

  # ── Who does get through ───────────────────────────────────────────────────

  test "a paid, active member's token unlocks it" do
    write_file
    post_referencing(audience: "paid")

    get AUDIO, params: { token: member.media_token }
    assert_response :success
    assert_equal "AUDIO BYTES", response.body
  end

  test "an admin gets it without a token" do
    write_file
    post_referencing(audience: "paid")
    sign_in_as(User.take)

    get AUDIO
    assert_response :success
  end

  # Revocation has to be immediate, which is why the token is checked against
  # the database rather than being a signed, self-contained one.
  test "a cancelled or downgraded member is refused" do
    write_file
    post_referencing(audience: "paid")

    get AUDIO, params: { token: member(status: :cancelled).media_token }
    assert_response :forbidden

    get AUDIO, params: { token: member(tier: :free).media_token }
    assert_response :forbidden
  end

  test "a made-up token is refused" do
    write_file
    post_referencing(audience: "paid")

    # A well-formed UUID that belongs to nobody — the lookup is by value, not
    # by shape. Deliberately all-zeros: a realistic-looking one is high-entropy
    # enough that secret scanners flag it as a leaked key.
    get AUDIO, params: { token: "00000000-0000-0000-0000-000000000000" }
    assert_response :forbidden
  end

  # access_token is the magic-link SIGN-IN token. It must not double as a file
  # credential, or a leaked image URL would be an account takeover.
  test "the sign-in token does not unlock files" do
    write_file
    post_referencing(audience: "paid")

    get AUDIO, params: { token: member.access_token }
    assert_response :forbidden
  end

  # ── Free media is untouched ────────────────────────────────────────────────

  test "a free post's audio is public" do
    write_file
    post_referencing(audience: "everyone")

    get AUDIO
    assert_response :success
  end

  test "a file nothing references is public" do
    write_file

    get AUDIO
    assert_response :success
  end

  # Public wins. Editing an unrelated paid post must never take down an image
  # on a page anyone can read.
  test "a file used by both paid and free content stays public" do
    write_file
    post_referencing(audience: "paid")
    page_referencing(audience: "everyone")

    get AUDIO
    assert_response :success
  end

  # And it flips back when the free reference goes away.
  test "removing the last free reference protects the file again" do
    write_file
    post_referencing(audience: "paid")
    free_page = page_referencing(audience: "everyone")
    get AUDIO
    assert_response :success

    free_page.destroy
    get AUDIO
    assert_response :forbidden
  end

  # ── Range requests still work ──────────────────────────────────────────────

  test "a range request is served, and authorized the same way" do
    write_file
    post_referencing(audience: "paid")

    get AUDIO, headers: { "Range" => "bytes=0-4" }
    assert_response :forbidden

    get AUDIO, params: { token: member.media_token }, headers: { "Range" => "bytes=0-4" }
    assert_response :partial_content
    assert_equal "AUDIO", response.body
    assert_equal "bytes 0-4/11", response.headers["Content-Range"]
  end

  # ── Variants ───────────────────────────────────────────────────────────────
  #
  # A variant is a resized copy of its source at <dir>/variants/<base>-<size>,
  # and it has no Medium row of its own. Checking the requested path directly
  # missed every time, so a paid image's variants were public — the full-size
  # original 403'd while an 1800px copy of it didn't.

  IMAGE = "/media/images/photo.jpg"
  VARIANT = "/media/images/variants/photo-medium.jpg"
  WEBP_VARIANT = "/media/images/variants/photo-medium.webp"

  def write_image
    [ IMAGE, VARIANT, WEBP_VARIANT ].each do |path|
      absolute = File.join(RoeSitePaths::SITE_PATH, path.delete_prefix("/"))
      FileUtils.mkdir_p(File.dirname(absolute))
      File.write(absolute, "IMAGE BYTES")
    end
    Medium.find_or_create_by!(file_path: IMAGE) { |m| m.media_type = "images" }
  end

  test "a paid image's variants are protected too" do
    write_image
    post_referencing(audience: "paid", path: IMAGE)

    get VARIANT
    assert_response :forbidden
  end

  # The WebP sibling is generated for every native variant, so its extension
  # differs from the source's — matching on the full path would miss it.
  test "the webp sibling is protected despite the different extension" do
    write_image
    post_referencing(audience: "paid", path: IMAGE)

    get WEBP_VARIANT
    assert_response :forbidden
  end

  test "a paid image's variant opens with a member token" do
    write_image
    post_referencing(audience: "paid", path: IMAGE)

    get VARIANT, params: { token: member.media_token }
    assert_response :success
  end

  test "a free image's variants stay public" do
    write_image
    post_referencing(audience: "everyone", path: IMAGE)

    get VARIANT
    assert_response :success
  end

  # Filenames routinely contain underscores, which are single-character
  # wildcards in SQL LIKE — the source lookup builds an exact list instead.
  test "an underscore in the filename doesn't match a different file" do
    Medium.create!(file_path: "/media/images/ben_patterns.jpg", media_type: "images")
    candidates = Medium.source_paths_for("/media/images/variants/ben_patterns-medium.webp")

    assert_includes candidates, "/media/images/ben_patterns.jpg"
    assert_not_includes candidates, "/media/images/ben-patterns.jpg"
  end

  # A file inside a variants directory that doesn't end in a known size isn't
  # one of ours; judge it on its own path rather than guessing at a source.
  test "an unrecognised file in a variants directory is judged on itself" do
    assert_equal [ "/media/images/variants/hand-made.jpg" ],
                 Medium.source_paths_for("/media/images/variants/hand-made.jpg")
  end

  test "a plain path is returned unchanged" do
    assert_equal [ IMAGE ], Medium.source_paths_for(IMAGE)
  end
end
