# Fake newsletter sends and failures, for looking at the UI.
#
# The failure states are the hard ones to produce on purpose — you'd have to
# get Postmark to reject a message — so this writes the rows directly. Same
# guard as members:seed_manual_test: development, or an explicit opt-in.
#
#   bin/rails newsletter:seed_manual_test    # build them (safe to re-run)
#   bin/rails newsletter:clear_manual_test   # remove every trace
#
# Only touches rows it created: members under example.test, and sends whose
# error text carries the marker below.
module ManualTestNewsletter
  MARKER = "[seeded]".freeze
  DOMAIN = "example.test".freeze

  # Real Postmark rejections, so the panel's grouping looks like it would in
  # practice rather than showing one invented string.
  REASONS = [
    "Inactive recipient",
    "Invalid email address",
    "Message contains no recipients",
    "Account is pending approval"
  ].freeze

  def self.allowed?
    Rails.env.development? || ENV["ROE_ALLOW_TEST_MEMBERS"] == "1"
  end

  def self.refusal
    "Refusing to run in #{Rails.env}. Set ROE_ALLOW_TEST_MEMBERS=1 if you mean it — " \
    "this writes fake delivery history into whatever database it's pointed at."
  end
end

namespace :newsletter do
  desc "Fake newsletter sends + failures so the UI can be looked at (development)"
  task seed_manual_test: :environment do
    abort ManualTestNewsletter.refusal unless ManualTestNewsletter.allowed?

    post = Post.published.order(created_at: :desc).first
    abort "No published post to attach sends to." unless post

    members = 12.times.map do |i|
      Member.find_or_create_by!(email: "nl-#{i}@#{ManualTestNewsletter::DOMAIN}") do |m|
        m.name = "Newsletter Tester #{i}"
        m.status = :active
        m.tier = :free
        m.newsletter_status = :subscribed
      end
    end

    # Eight delivered, four failed — a partial failure, which is the case the
    # panel used to report as a clean success.
    delivered, failed = members.each_slice(8).to_a

    delivered.each_with_index do |member, i|
      NewsletterSend.record!(post: post, member: member, message_id: "seeded-#{post.id}-#{i}")
    end

    failed.each_with_index do |member, i|
      reason = ManualTestNewsletter::REASONS[i % ManualTestNewsletter::REASONS.size]
      NewsletterSend.record!(post: post, member: member,
                             error: "#{reason} #{ManualTestNewsletter::MARKER}")
    end

    base = SiteConfig.site_url.to_s.chomp("/").presence || "http://localhost:3000"

    puts "\nSeeded against: #{post.title}"
    puts "  #{delivered.size} delivered, #{failed.size} failed\n\n"
    puts "  Post panel:   #{base}/admin/posts/#{post.id}/edit"
    puts "  A failure:    #{base}/admin/members/#{failed.first.id}"
    puts "  A success:    #{base}/admin/members/#{delivered.first.id}"
    puts "\n  Remove: bin/rails newsletter:clear_manual_test\n\n"
  end

  desc "Remove everything newsletter:seed_manual_test created"
  task clear_manual_test: :environment do
    abort ManualTestNewsletter.refusal unless ManualTestNewsletter.allowed?

    members = Member.where("email LIKE ?", "%@#{ManualTestNewsletter::DOMAIN}")
                    .where("email LIKE ?", "nl-%")
    sends = NewsletterSend.where(member_id: members.ids)
             .or(NewsletterSend.where("error LIKE ?", "%#{ManualTestNewsletter::MARKER}%"))

    send_count = sends.count
    member_count = members.count
    sends.delete_all
    members.destroy_all

    puts "Removed #{send_count} sends and #{member_count} members."
  end
end
