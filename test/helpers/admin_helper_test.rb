require "test_helper"

# useful_links builds the "Show Links" panel in the layout editor. It should
# list one podcast feed per show: the public /podcast/<key>.xml for open shows,
# and the private URL for paid-only shows (which have no public feed).
class AdminHelperTest < ActionView::TestCase
  include AdminHelper

  setup { stubs(:members_enabled?).returns(false) }

  test "useful_links lists a public feed per open podcast show" do
    PodcastConfig.stubs(:podcast_keys).returns([ "show-a", "show-b" ])
    PodcastConfig.stubs(:get).with("show-a").returns({ "title" => "Show A" })
    PodcastConfig.stubs(:get).with("show-b").returns({ "title" => "Show B" })

    podcasts = useful_links[:podcasts]

    assert_equal "/podcast/show-a.xml", podcasts["Show A"]
    assert_equal "/podcast/show-b.xml", podcasts["Show B"]
  end

  test "a paid-only show links its private feed instead" do
    PodcastConfig.stubs(:podcast_keys).returns([ "members-only" ])
    PodcastConfig.stubs(:get).with("members-only")
      .returns({ "title" => "Members Only", "audience" => "paid" })

    podcasts = useful_links[:podcasts]

    assert_nil podcasts["Members Only"]
    assert_equal "/podcast/members-only/private.xml", podcasts["Members Only (private)"]
  end

  test "no podcasts section when there are no shows" do
    PodcastConfig.stubs(:podcast_keys).returns([])

    assert_nil useful_links[:podcasts]
  end
end
