# frozen_string_literal: true

require "test_helper"

# The static build is served straight from disk by StaticSiteMiddleware, and
# STATIC_SITE_PATH lives outside current/ — so baked HTML survives every update
# and deploy. If the layout's Snipcart markup didn't reach the static build, a
# store would keep serving pre-fix pages no matter how current the code was.
class StaticSnipcartMarkupTest < ActiveSupport::TestCase
  setup do
    @path = File.join(RoeSitePaths::SITE_PATH, "pages", "zz-static-cart.md")
    File.write(@path, "---\ntitle: \"ZZ Static Cart\"\nurl_name: zz-static-cart\nstatus: published\n---\nBody.\n")
    @page = Page.create_or_update_from_file(@path)

    config = SnipcartConfig.new
    config.stubs(:current_snippet).returns(
      %(<script src="https://cdn.snipcart.com/themes/v3.7.2/default/snipcart.js"></script>)
    )
    config.stubs(:connected?).returns(true)
    config.stubs(:currency).returns("USD")
    config.stubs(:current_snippet_html).returns(
      %(<script data-turbo-eval="false" src="https://cdn.snipcart.com/themes/v3.7.2/default/snipcart.js"></script>).html_safe
    )
    SnipcartConfig.stubs(:current).returns(config)
    SiteFeature.stubs(:store_enabled?).returns(true)
  end

  teardown do
    FileUtils.rm_f(@path)
    Page.where(file_path: @path).destroy_all
  end

  # Exactly how StaticGenerator#render_with_layout renders a page.
  def static_html
    prior = Current.static_generation
    Current.static_generation = true
    Current.member = nil
    ApplicationController.render(
      template: "pages/show",
      assigns: { page: @page, static_generation: true },
      layout: "site"
    )
  ensure
    Current.static_generation = prior
  end

  test "the static build bakes in the permanent #snipcart container" do
    html = static_html

    assert_includes html, 'id="snipcart"',
      "without it, Turbo destroys Snipcart's own div on the first navigation"
    assert_includes html, "data-turbo-permanent",
      "the container has to survive the body swap, not just exist"
  end

  test "the static build carries the loader marked against Turbo re-execution" do
    assert_includes static_html, 'data-turbo-eval="false"',
      "re-running the loader appends another snipcart.js on every navigation"
  end

  # Snipcart drops data-turbo-permanent when it mounts, so the server-rendered
  # attribute alone never survives to the moment Turbo needs it.
  test "the container is re-marked permanent after Snipcart mounts" do
    html = static_html

    assert_includes html, "turbo:before-render",
      "without the re-mark, Turbo's permanent-element map is empty and the container dies with the body"
    assert_includes html, "MutationObserver",
      "the event alone misses a node Snipcart replaced rather than stripped"
  end

  # Snipcart writes the item count into a <sup> the server renders empty on
  # every page, so a body swap replaced the populated node with a blank one.
  test "the cart link is preserved so its item count survives a navigation" do
    html = static_html

    assert_match %r{<a[^>]*id="snipcart-cart-link"[^>]*data-turbo-permanent}, html,
      "Turbo matches permanent elements by id — without one the link is swapped and the count blanks"
  end

  # Turbo re-executes body scripts on every visit. Ours register listeners and
  # observers, so each navigation was stacking another set.
  test "the inline Snipcart scripts don't re-run on every visit" do
    html = static_html

    # Ours only — Rails' importmap module tag is not ours to mark, and an ES
    # module re-import is a no-op anyway.
    ours = html.scan(/<script\b(?![^>]*\bsrc=)([^>]*)>(.*?)<\/script>/m).select do |_attrs, body|
      body.match?(/SnipcartSettings|turbo:before-render|snipcart-cart--opened|roeSnipcartDebug/)
    end

    assert_equal 4, ours.length, "expected the currency, re-mark, diagnostics and shield scripts"
    ours.each do |attrs, body|
      assert_includes attrs, 'data-turbo-eval="false"',
        "this script re-runs on every visit, stacking a duplicate listener each time: #{body[0, 60].strip}"
    end
  end

  # The shield reads Snipcart's classes off <html> and stops Turbo's popstate
  # handler while the cart is open. It's an inline script, and inline scripts
  # are exactly what a static build tends to drop.
  test "the static build keeps the popstate shield" do
    assert_includes static_html, "snipcart-cart--opened",
      "closing the cart pops onto Turbo's entry and triggers a restoration visit"
  end
end
