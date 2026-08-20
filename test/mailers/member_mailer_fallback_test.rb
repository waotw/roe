# frozen_string_literal: true

require "test_helper"

# With no Postmark token, MemberMailer hands off to ActionMailer. That's a real
# delivery path in development, where letter_opener catches the mail. In
# production it's SMTP against settings nobody filled in — localhost:25 — and
# Rails raises delivery errors by default, with nothing catching them. A members
# site with no token answered sign-in with a 500.
class MemberMailerFallbackTest < ActiveSupport::TestCase
  def setup
    super
    PostmarkConfig.delete_all
    @member = create(:member, email: "reader@example.com", tier: :free, status: :active)
  end

  def send_magic_link = MemberMailer.magic_link(@member)

  test "a delivery failure doesn't take the sign-in down with it" do
    FallbackMailer.any_instance.stubs(:mail).raises(Errno::ECONNREFUSED, "localhost:25")

    result = assert_nothing_raised { send_magic_link }

    assert_not result[:success], "and it says the mail didn't go"
    assert result[:fallback]
  end

  test "a fallback that does deliver reports success" do
    ActionMailer::Base.deliveries.clear

    result = send_magic_link

    assert result[:success]
    assert result[:fallback], "still worth knowing it wasn't Postmark"
    assert_equal 1, ActionMailer::Base.deliveries.size
  end
end
