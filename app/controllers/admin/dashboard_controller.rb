class Admin::DashboardController < Admin::BaseController
  def index
    @posts_count = Post.count
    @published_posts_count = Post.published.count
    @draft_posts_count = Post.drafts.count
    @pages_count = Page.count

    return unless SiteFeature.payments_enabled?

    if SiteFeature.memberships_enabled?
      paid = Member.tier_paid
      @paid_members_count = paid.count
      # Sum only members with a recorded amount snapshot. Older paid
      # members (pre-tracking) appear in the count but not the total.
      @membership_revenue_cents = paid.where.not(paid_amount_cents: nil).sum(:paid_amount_cents)
      @membership_untracked_count = paid.where(paid_amount_cents: nil).count
      @membership_currency = paid.where.not(paid_currency: nil).pick(:paid_currency)
    end

    if SiteFeature.donations_enabled?
      @donations_count = Donation.count
      @donations_total_cents = Donation.total_cents
      @donations_currency = Donation.where.not(currency: nil).pick(:currency)
    end

    # Refund totals across BOTH revenue sources. We display one combined
    # number — drilldown by source lives in Stripe.
    refunded_donations = Donation.where.not(refunded_at: nil)
    refunded_members = Member.where.not(refunded_at: nil)
    @refunds_count = refunded_donations.count + refunded_members.count
    @refunds_total_cents = refunded_donations.sum(:refunded_amount_cents) +
                           refunded_members.sum(:refunded_amount_cents)
    @refunds_currency = refunded_donations.where.not(refunded_currency: nil).pick(:refunded_currency) ||
                        refunded_members.where.not(refunded_currency: nil).pick(:refunded_currency)

    # Open disputes banner. We only need the count to drive the banner;
    # the user reviews details in Stripe.
    @open_disputes_count = Dispute.currently_open.count

    # Net totals across every payments row (memberships + donations - refunds).
    # Used by the TOTAL row at the bottom of the Payments table.
    @total_transactions_count = @paid_members_count.to_i + @donations_count.to_i + @refunds_count.to_i
    @total_amount_cents = @membership_revenue_cents.to_i + @donations_total_cents.to_i - @refunds_total_cents.to_i
    @total_currency = @membership_currency || @donations_currency || @refunds_currency

    # Mode-aware Stripe deep links so the dashboard "view in Stripe"
    # links land in the right environment.
    test_mode = StripeConfig.current.mode_test?
    stripe_base = test_mode ? "https://dashboard.stripe.com/test" : "https://dashboard.stripe.com"
    @stripe_refunds_url = "#{stripe_base}/payments?status%5B0%5D=refunded"
    @stripe_disputes_url = "#{stripe_base}/disputes"
  end
end
