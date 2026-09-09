require "test_helper"

# A paywall offering only "Become a paid member" strands someone who has
# already paid: no way in from the page they landed on, and the upgrade page
# has to load before they discover one.
class PaidContentSigninTest < ActiveSupport::TestCase
  class Renderer
    include HasMarkdownExtensions
  end

  setup do
    @r = Renderer.new
    SiteFeature.stubs(:members_enabled?).returns(true)
    SiteFeature.stubs(:payments_enabled?).returns(true)
    # The test site carries no member pages, so the real lookup correctly
    # returns nil and the line wouldn't render at all.
    MemberPages.stubs(:url_for).with("signin").returns("/sign-in")
    MemberPages.stubs(:url_for!).with("upgrade").returns("/upgrade")
  end

  def render(config)
    @r.send(:render_form, { "for" => "paid_content" }.merge(config))
  end

  test "the sign-in line renders without being asked for" do
    html = render({})

    assert_match "Already a member?", html
    assert_match ">Sign in</a>", html
  end

  test "only the bracketed words are linked" do
    html = render({})

    assert_match(/Already a member\? <a [^>]*>Sign in<\/a>\./, html,
      "the brackets name the link text; the rest is plain")
    assert_no_match(/\[Sign in\]/, html, "the brackets themselves shouldn't survive")
  end

  test "the author can change the wording" do
    html = render({ "signin-text" => "Got an account? [Click here] to read on." })

    assert_match "Got an account?", html
    assert_match ">Click here</a>", html
  end

  test "signin_text is accepted alongside signin-text" do
    html = render({ "signin_text" => "Members [log in] here." })

    assert_match ">log in</a>", html
  end

  # A sentence with no brackets still has to be clickable.
  test "text with no brackets links the whole sentence" do
    html = render({ "signin-text" => "Sign in to keep reading" })

    assert_match(/<a [^>]*>Sign in to keep reading<\/a>/, html)
  end

  # The URL comes from the page, so renaming it can't leave dead links behind.
  test "the link follows the sign-in page's url_name" do
    MemberPages.stubs(:url_for).with("signin").returns("/members/enter")

    assert_match 'href="/members/enter"', render({})
  end

  test "the upgrade button follows its page too" do
    MemberPages.stubs(:url_for!).with("upgrade").returns("/join-us")

    assert_match 'href="/join-us"', render({})
  end

  # It doesn't render when it can't work — which is the only case anyone would
  # reasonably want it gone, so there's no option to switch it off.
  test "nothing renders when there's no sign-in page to link to" do
    MemberPages.stubs(:url_for).with("signin").returns(nil)

    assert_no_match "Already a member?", render({})
  end

  # The link works wherever the brackets sit, not only at the end.
  test "the brackets can be anywhere in the sentence" do
    assert_match(/<a [^>]*>Sign in<\/a>, if you like/,
                 render({ "signin-text" => "[Sign in], if you like" }))
    assert_match(/words <a [^>]*>here<\/a> more/,
                 render({ "signin-text" => "words [here] more" }))
  end

  # YAML reads a value opening with `[` as a list, so the block fails to parse
  # before any of this runs. Psych's own message names its parser rather than
  # the mistake, so the warning has to.
  # Warns where an author can act on it, and nowhere a reader could see it —
  # checked across preview, development, a published page, the static build and
  # the feed. Under RAILS_ENV=test none of those are true by default, so an
  # assertion written without setting one passes whether or not the warning
  # exists.
  BAD_BLOCK = "```form\nfor: paid_content\nsignin_text: [Sign in], If you want\n```\n"

  test "a value starting with a bracket explains itself, to the author only" do
    assert_block_warning BAD_BLOCK, matching: /which YAML reads as a list/
  end

  test "the warning shows the corrected line rather than describing it" do
    html = render_block(BAD_BLOCK, context: :preview)

    assert_match 'signin_text: "[Sign in], If you want"', html
  end

  test "a well-formed block warns nowhere" do
    assert_no_block_warning "```form\nfor: paid_content\nsignin_text: Already a member? [Sign in].\n```\n",
      metadata: { "audience" => "paid" }
  end

  test "quoting it makes the same value work" do
    html = @r.send(:process_forms, "```form\nfor: paid_content\nsignin_text: \"[Sign in], If you want\"\n```\n")

    assert_match(/<a [^>]*>Sign in<\/a>, If you want/, html)
  end

  test "the sentence is escaped" do
    html = render({ "signin-text" => "<script>alert(1)</script> [in]" })

    assert_no_match "<script>alert", html
  end
end
