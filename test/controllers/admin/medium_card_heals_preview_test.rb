require "test_helper"

# An image whose admin preview was never made stayed "pending" for good: the
# Media page polled its card on every visit, and each swap showed it under
# every tab. Animated GIFs added before their thumb counted as their preview
# were the real case — no job was ever queued for them. Polling the card now
# queues the missing preview.
class Admin::MediumCardHealsPreviewTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  DIR = File.join(RoeSitePaths::SITE_PATH, "media", "images", "heal_test").freeze

  setup do
    sign_in_as(User.take)
    FileUtils.mkdir_p(DIR)
    @path = File.join(DIR, "stuck.gif")
    # Two frames: animated, so its only preview is the thumb.
    gif = +"GIF89a".b
    gif << [ 1, 1 ].pack("v2") << "\x80\x00\x00".b << "\x00\x00\x00\xFF\xFF\xFF".b
    2.times { gif << "\x21\xF9\x04\x00\x0A\x00\x00\x00".b << "\x2C".b << [ 0, 0, 1, 1 ].pack("v4") << "\x00".b << "\x02\x02\x44\x01\x00".b }
    gif << "\x3B".b
    File.binwrite(@path, gif)

    ImageVariantGenerator.stubs(:available?).returns(true)
    # Added the old way: no preview, no job. insert_all skips after_create,
    # which would queue it.
    @web = "/media/images/heal_test/stuck.gif"
    Medium.insert_all([ { file_path: @web, media_type: "images", variants_status: "pending",
                          created_at: Time.current, updated_at: Time.current } ])
    @medium = Medium.find_by!(file_path: @web)
  end

  teardown do
    FileUtils.rm_rf(DIR)
    Medium.where(file_path: @web).delete_all
  end

  test "polling the card of an image with no preview queues the preview" do
    assert_not @medium.baseline_ready?

    assert_enqueued_with(job: GenerateImageVariantsJob, args: [ @web, nil, false, [ "thumb" ] ]) do
      get card_admin_medium_path(@medium), as: :json
    end
    assert response.parsed_body["pending"]
  end

  test "an image whose preview exists isn't queued again" do
    ImageVariantGenerator.stubs(:baseline_exists?).returns(true)

    assert_no_enqueued_jobs(only: GenerateImageVariantsJob) do
      get card_admin_medium_path(@medium), as: :json
    end
    assert_not response.parsed_body["pending"]
  end
end
