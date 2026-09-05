# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Roe had no way to answer a URL it used to serve: a same-domain move onto Roe
# leaves every inbound link pointing at the old shape, and renaming a url_name
# breaks every existing link to that page.
class SiteRedirectsTest < ActionDispatch::IntegrationTest
  setup do
    @path = SiteRedirectsMiddleware::CONFIG_PATH
    @original = File.exist?(@path) ? File.read(@path) : nil
    FileUtils.mkdir_p(File.dirname(@path))
  end

  teardown do
    @original ? File.write(@path, @original) : FileUtils.rm_f(@path)
    SiteRedirectsMiddleware.reload!
  end

  def with_rules(yaml)
    File.write(@path, yaml)
    SiteRedirectsMiddleware.reload!
  end

  # An install with no redirects.yml has no way to discover the feature exists.
  # The minimum kit is installed on every boot, skipping anything already in
  # /site, so seeding it there reaches existing installs too.
  #
  # Installed into a temp directory rather than by calling generate_all: that
  # also runs the security and navigation migrations against the shared test
  # site, which broke RobotsTest and SearchIndexGeneratorTest on some run
  # orders. The loader is the part being tested either way.
  def install_kit_into(destination)
    SiteTemplates::Loader.install(
      folder: "minimum", destination: destination, locals: { today: Date.today }
    )
  end

  test "a fresh install gets a redirects.yml to edit" do
    Dir.mktmpdir do |dir|
      install_kit_into(dir)
      seeded = File.join(dir, "system", "global", "redirects.yml")

      assert File.exist?(seeded), "nothing seeded it, so the feature is invisible"
      assert_equal [ "redirects" ], YAML.safe_load(File.read(seeded)).keys,
        "the seeded file should show the shape to fill in and nothing else"
    end
  end

  # The seeded file has the key with no value, which parses to nil rather than
  # an empty map — so nil has to be as inert as {} is.
  test "the stock file redirects nothing until a rule is written" do
    with_rules("redirects:\n")

    get "/anything-at-all"

    assert_response :not_found
  end

  # "/blog/*" → "/blog" sends every request back to itself. A browser answers
  # that with a redirect-loop error page instead of the content.
  test "a rule that points at itself is ignored, not served as a loop" do
    with_rules(%(redirects:\n  \"/p/*\": \"/p\"\n))

    get "/p/my-post"

    assert_response :not_found, "a typo cost the URL instead of just the redirect"
  end

  # Same guarantee every other seeded config relies on.
  test "seeding never overwrites redirects someone has written" do
    Dir.mktmpdir do |dir|
      seeded = File.join(dir, "system", "global", "redirects.yml")
      FileUtils.mkdir_p(File.dirname(seeded))
      File.write(seeded, %(redirects:\n  \"/mine\": \"/kept\"\n))

      install_kit_into(dir)

      assert_match "/mine", File.read(seeded)
    end
  end

  # Both are added by `use`, so their order comes from initializer filenames
  # sorting — rename either file and a redirect would lose to a static file
  # with nothing to say so.
  test "a redirect is answered before the static build gets the request" do
    names = Rails.application.middleware.map { |m| m.klass.to_s }

    assert_operator names.index("SiteRedirectsMiddleware"), :<,
                    names.index("StaticSiteMiddleware"),
                    "a baked page would win over the redirect meant to replace it"
  end

  test "an exact path redirects, permanently by default" do
    with_rules(%(redirects:\n  \"/old-home\": \"/\"\n))

    get "/old-home"

    assert_response :moved_permanently
    assert_equal "/", response.headers["Location"]
  end

  # The Substack shape: /p/<slug> is where every inbound link still points.
  test "a prefix rule carries the rest of the path" do
    with_rules(%(redirects:\n  \"/p/*\": \"/posts\"\n))

    get "/p/my-first-post"

    assert_response :moved_permanently
    assert_equal "/posts/my-first-post", response.headers["Location"]
  end

  # Git asks for /roe.git/info/refs?service=git-upload-pack. Drop the query and
  # it falls back to the dumb protocol and fails.
  test "the query string survives, which is what git needs" do
    with_rules(%(redirects:\n  \"/roe.git/*\":\n    to: \"https://github.com/waotw/roe\"\n    status: 301\n))

    get "/roe.git/info/refs?service=git-upload-pack"

    assert_response :moved_permanently
    assert_equal "https://github.com/waotw/roe/info/refs?service=git-upload-pack",
                 response.headers["Location"]
  end

  test "a temporary redirect can be asked for" do
    with_rules(%(redirects:\n  \"/moved\":\n    to: \"/somewhere\"\n    status: 302\n))

    get "/moved"

    assert_response :found
  end

  # A typo in redirects.yml must not be able to lock someone out of the admin
  # that would let them fix it.
  test "Roe's own paths can't be redirected away" do
    with_rules(%(redirects:\n  \"/admin/*\": \"https://hijacked.invalid\"\n))

    get "/admin"

    # Unauthenticated, so a redirect to sign-in is expected — just not ours.
    assert_no_match %r{hijacked\.invalid}, response.headers["Location"].to_s,
      "a typo in redirects.yml could lock someone out of the admin that would fix it"
  end

  test "a path with no rule is left alone" do
    with_rules(%(redirects:\n  \"/p/*\": \"/posts\"\n))

    get "/nothing-here"

    assert_response :not_found
  end

  # A broken redirects file must not take the site down with it.
  test "invalid YAML disables redirects rather than the site" do
    with_rules("this: [is: broken\n")

    get "/p/anything"

    assert_response :not_found
  end

  test "no redirects file at all is fine" do
    FileUtils.rm_f(@path)
    SiteRedirectsMiddleware.reload!

    get "/nothing-here"

    assert_response :not_found
  end
end
