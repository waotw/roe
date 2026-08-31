class Admin::DashboardController < Admin::BaseController
  def index
    @content_blocks = content_blocks

    # Backups: recorded when they change, not walked on every page load —
    # see SiteSync::BackupStats.
    @backup_stats  = SiteSync::BackupStats.current
    @database_size = database_bytes

    # Pages Roe installed that lost their status and now 404 for logged-out
    # visitors. Surfaced rather than repaired silently — see PageStatusRepair.
    @pages_needing_status = PageStatusRepair.count

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

  private

  # Published / Unlisted / Drafts, plus anything belonging to none of them.
  #
  # The status scopes match the raw JSON exactly, while #status defaults a
  # missing value to "draft" — so a page with no status is in no scope at all
  # and used to vanish from the totals. Counting the remainder means the
  # column always adds up to Total, and an odd one is visible rather than lost.
  # One block per thing worth counting separately.
  #
  # Posts is scoped to articles whenever a type has its own block, so the grid
  # partitions rather than double-counting — an episode shouldn't be in both
  # Posts and Episodes. Episodes, Tracks and Products only appear when there's
  # something in them, so a blog stays a two-block grid.
  def content_blocks
    blocks = []

    typed = [
      [ "Episodes", "podcast", ->(s) { admin_posts_path(type: "podcast", status: s) } ],
      [ "Tracks",   "music",   ->(s) { admin_posts_path(type: "music",   status: s) } ]
    ].select { |_label, type, _path| Post.by_type(type).any? }

    posts_scope = typed.any? ? Post.by_type("article") : Post.all
    posts_label = typed.any? ? "Articles" : "Posts"
    posts_filter = typed.any? ?
      ->(s) { admin_posts_path(type: "article", status: s) } :
      ->(s) { admin_posts_path(status: s) }

    blocks << block(posts_label, posts_scope, admin_posts_path, posts_filter)

    typed.each do |label, type, filter|
      blocks << block(label, Post.by_type(type), admin_posts_path(type: type), filter)
    end

    blocks << block("Pages", Page.all, admin_pages_path, ->(_s) { admin_pages_path })
    blocks << block("Products", Product.all, admin_products_path, ->(_s) { admin_products_path }) if Product.any?

    blocks
  end

  def block(label, scope, index_path, filter_path)
    { label: label, index_path: index_path, filter_path: filter_path, stats: content_breakdown(scope) }
  end

  def content_breakdown(model)
    published = model.published.count
    unlisted  = model.unlisted.count
    drafts    = model.drafts.count
    total     = model.count

    {
      published: published,
      unlisted:  unlisted,
      drafts:    drafts,
      unset:     total - published - unlisted - drafts,
      total:     total
    }
  end

  def database_bytes
    File.size(ActiveRecord::Base.connection_db_config.database)
  rescue StandardError
    nil
  end
end
