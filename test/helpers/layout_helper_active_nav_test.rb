require "test_helper"

# LayoutHelper#add_active_nav_class highlights the current page's link. The
# file-level default (header on, footer/sidebar off) is passed as default_on;
# a `menu` block overrides it for its own links with data-show-active on the
# <ul>. Here we feed the method HTML directly and assert which links get the
# `active` class, so the default + per-menu override logic is covered without a
# full page render.
class LayoutHelperActiveNavTest < ActionView::TestCase
  include LayoutHelper

  # Stand-in for the current content object; only url_name is read.
  Current = Struct.new(:url_name)

  def highlight(html, current: Current.new("about"), default_on: true)
    send(:add_active_nav_class, html, current, default_on: default_on)
  end

  def active?(html)
    html.include?('class="active"') || html.include?(" active")
  end

  # --- plain links follow the file default ---------------------------------

  test "a matching plain link is highlighted when default_on" do
    out = highlight(%(<a href="/about">About</a>), default_on: true)
    assert active?(out)
  end

  test "a matching plain link is NOT highlighted when default_off" do
    out = highlight(%(<a href="/about">About</a>), default_on: false)
    assert_not active?(out)
  end

  test "a non-matching link is never highlighted" do
    out = highlight(%(<a href="/store">Store</a>), default_on: true)
    assert_not active?(out)
  end

  # --- a menu block's data-show-active overrides the file default ----------

  test "data-show-active=false suppresses the highlight even when default_on" do
    html = %(<ul data-show-active="false"><li><a href="/about">About</a></li></ul>)
    assert_not active?(highlight(html, default_on: true))
  end

  test "data-show-active=true forces the highlight even when default_off" do
    html = %(<ul data-show-active="true"><li><a href="/about">About</a></li></ul>)
    assert active?(highlight(html, default_on: false))
  end

  test "a menu without the attribute follows the file default" do
    html = %(<ul class="collection-menu"><li><a href="/about">About</a></li></ul>)
    assert active?(highlight(html, default_on: true))
    assert_not active?(highlight(html, default_on: false))
  end

  # --- home matching (href '/') --------------------------------------------

  test "home link matches on the home page when default_on" do
    out = highlight(%(<a href="/">Home</a>), current: Current.new("home"), default_on: true)
    assert active?(out)
  end
end
