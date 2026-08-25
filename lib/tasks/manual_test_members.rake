# Throwaway members for testing account deletion by hand.
#
# Deletion is the one feature you can't sensibly test on your own account, and
# the cases that matter differ by what's behind each member: a payment, a
# donation, a newsletter history, or nothing at all. This builds one of each.
#
# Development only, and every address is under `.test` — reserved by RFC 6761
# precisely so it can never resolve, so nothing can escape even if a send is
# triggered by accident.
#
#   bin/rails members:seed_manual_test    # build them (safe to re-run)
#   bin/rails members:clear_manual_test   # remove every trace
#
# Deleting a seeded member during testing renames them, so their address is no
# longer recognisable. The ids are kept in tmp/ for that reason; the cleanup
# matches on either, and touches nothing outside this set.
module ManualTestMembers
  DOMAIN   = "example.test"
  MANIFEST = "tmp/manual_test_members.json"

  def self.manifest = Rails.root.join(MANIFEST)
end

namespace :members do

  desc "Create throwaway members for testing account deletion (development only)"
  task seed_manual_test: :environment do
    abort "Development only — refusing to run in #{Rails.env}." unless Rails.env.development?

    posts = Post.published.order(created_at: :desc).to_a
    abort "No published posts to build a newsletter history from." if posts.empty?

    ids = []

    build = lambda do |email, **attrs|
      member = Member.find_or_initialize_by(email: "#{email}@#{ManualTestMembers::DOMAIN}")
      member.assign_attributes({ status: :active, tier: :free,
                                 newsletter_status: :subscribed }.merge(attrs))
      member.save!
      ids << member.id
      member
    end

    sends = lambda do |member, count|
      posts.first(count).each_with_index do |post, i|
        NewsletterSend.find_or_create_by!(member: member, post: post) do |s|
          s.sent_at = (count - i).weeks.ago
          s.message_id = "manual-test-#{member.id}-#{post.id}"
        end
      end
    end

    # Nothing behind them. The one case Delete Member removes outright — a
    # spam signup shouldn't leave a permanent stub in the members list.
    build.call("erasable", name: "Erasable Signup")

    # Newsletter history and no money. Deleting this one must keep every send:
    # that history is the site's own record, not the member's.
    sends.call(build.call("newsletters", name: "Nora Newsletter"), 4)

    # Paid, with a history. Use this one for the member-facing flow — it can
    # read paid content, so it has private feed URLs on its account page.
    paid = build.call("paid", name: "Paula Paid",
                      tier: :paid, paid_at: 3.months.ago, paid_amount_cents: 5000,
                      paid_currency: "usd", subscribed_at: 3.months.ago,
                      stripe_customer_id: "cus_manualtest_paid",
                      stripe_payment_intent_id: "pi_manualtest_paid")
    sends.call(paid, 3)

    # Refunded, so you can check the refund columns survive deletion.
    build.call("refunded", name: "Rufus Refunded",
               tier: :free, paid_at: 6.months.ago, paid_amount_cents: 5000,
               paid_currency: "usd", subscribed_at: 6.months.ago,
               refunded_at: 5.months.ago, refunded_amount_cents: 5000,
               refunded_currency: "usd",
               stripe_payment_intent_id: "pi_manualtest_refunded")

    # Cancelled but not deleted — the badge should still read Cancelled after
    # this work, not Deleted. Given a newsletter history too: "cancelled" reads
    # like there's nothing left behind, which is exactly the assumption worth
    # testing against.
    sends.call(build.call("cancelled", name: "Colin Cancelled",
               tier: :paid, status: :cancelled, paid_at: 8.months.ago,
               paid_amount_cents: 2500, paid_currency: "usd",
               cancelled_at: 1.month.ago, subscribed_at: 8.months.ago,
               stripe_payment_intent_id: "pi_manualtest_cancelled"), 2)

    # A donor. Donations store their own copy of the address, which is the
    # part the old admin Delete button left behind.
    donor = build.call("donor", name: "Dina Donor")
    [ [ 2500, 2.months.ago ], [ 1000, 3.weeks.ago ] ].each_with_index do |(cents, at), i|
      Donation.find_or_create_by!(stripe_session_id: "cs_manualtest_#{donor.id}_#{i}") do |d|
        d.member = donor
        d.email = donor.email
        d.amount_cents = cents
        d.currency = "usd"
        d.created_at = at
        d.stripe_payment_intent_id = "pi_manualtest_donation_#{i}"
      end
    end

    FileUtils.mkdir_p(ManualTestMembers.manifest.dirname)
    ManualTestMembers.manifest.write(JSON.pretty_generate(ids.uniq))

    base = SiteConfig.site_url.to_s.chomp("/").presence || "http://localhost:3000"

    puts "\nSeeded #{ids.uniq.size} members. Sign in as one with:\n\n"
    Member.where(id: ids).order(:email).each do |m|
      puts "  #{m.email.ljust(28)} #{base}/signin/#{m.access_token}"
    end
    puts "\n  Admin → Members: #{base}/admin/members"
    puts "  Remove them all: bin/rails members:clear_manual_test\n\n"
  end

  desc "Remove the throwaway members created by members:seed_manual_test"
  task clear_manual_test: :environment do
    abort "Development only — refusing to run in #{Rails.env}." unless Rails.env.development?

    # By address for the ones still named, by id for any deleted during
    # testing — anonymising renames them, so the address alone would miss them.
    seeded = ManualTestMembers.manifest.exist? ? JSON.parse(ManualTestMembers.manifest.read) : []
    members = Member.where(id: seeded).or(Member.where("email LIKE ?", "%@#{ManualTestMembers::DOMAIN}"))

    if members.none?
      puts "Nothing to remove."
      next
    end

    emails = members.pluck(:email)
    Donation.where(member_id: members.ids).delete_all
    NewsletterSend.where(member_id: members.ids).delete_all
    members.destroy_all

    ManualTestMembers.manifest.delete if ManualTestMembers.manifest.exist?
    puts "Removed #{emails.size} members and their records: #{emails.sort.join(', ')}"
  end
end
