module Admin
  class MembersController < Admin::BaseController
    before_action :set_member, only: [ :show, :edit, :update, :destroy,
                                       :upgrade_to_paid, :downgrade_to_free,
                                       :cancel_membership, :reactivate_membership ]

    # A deleted account is a record, not a member. There's no one left to
    # upgrade, bill or sign in, and editing it would put a name and address
    # back on a row whose whole point is that it no longer has one.
    #
    # The page hides these controls; this is what makes them actually refuse,
    # since a hidden button is still a reachable URL.
    before_action :reject_deleted_account, only: [ :edit, :update, :destroy,
                                                   :upgrade_to_paid, :downgrade_to_free,
                                                   :cancel_membership, :reactivate_membership ]

    def index
      @members = Member.order(created_at: :desc)

      # Filter by tier/status if params present
      @members = @members.where(tier: params[:tier]) if params[:tier].present?
      @members = @members.where(status: params[:status]) if params[:status].present?

      # Search by email/name
      if params[:search].present?
        @members = @members.where("email LIKE ? OR name LIKE ?",
                                  "%#{params[:search]}%",
                                  "%#{params[:search]}%")
      end

      # Which filter controls to render. Tier checkboxes only make sense when
      # the site actually has both free and paid members — with one kind there
      # is nothing to filter. Imported only when some member came from an
      # import. Newsletter status only when newsletters are a feature at all.
      @has_free        = Member.free_tier.exists?
      @has_paid        = Member.paid_tier.exists?
      @show_tier_filter = @has_free && @has_paid
      @has_imported    = Member.imported.exists?
      @show_newsletter_filter = SiteFeature.newsletters_feature_enabled?
    end

    def show
      # Show member details, access token, membership history
    end

    def new
      @member = Member.new
    end

    def create
      @member = Member.new(member_params)

      if @member.save
        redirect_to admin_member_path(@member), notice: "Member created successfully"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      # Edit member details
    end

    def update
      if @member.update(member_params)
        redirect_to admin_member_path(@member), notice: "Member updated successfully"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Removing a member must not take the site's own records with it.
    #
    # A plain destroy did: newsletter_sends is `dependent: :destroy`, so the
    # delivery history went too, while donations were left pointing at a row
    # that no longer existed — still carrying the donor's real email. That
    # deleted the useful part and kept the private part.
    #
    # So: erase members with nothing behind them, anonymise the rest. Same
    # path a member takes deleting their own account (Member#anonymize!).
    def destroy
      if @member.erasable?
        @member.destroy
        redirect_to admin_members_path, notice: "Member deleted"
      else
        @member.anonymize!(by: :admin)
        redirect_to admin_member_path(@member),
          notice: "Member deleted. Their payment and newsletter records are kept without their name on them."
      end
    end

    # Manual upgrade to paid tier
    def upgrade_to_paid
      password = params[:password].presence || SecureRandom.hex(8)

      if @member.upgrade_to_paid!(password: password)
        flash[:notice] = "Upgraded to paid tier. Password: #{password}"
        redirect_to admin_member_path(@member)
      else
        flash[:alert] = "Failed to upgrade: #{@member.errors.full_messages.join(', ')}"
        redirect_to admin_member_path(@member)
      end
    end

    # Manual downgrade to free tier
    def downgrade_to_free
      @member.update!(tier: :free, password_digest: nil)
      redirect_to admin_member_path(@member), notice: "Downgraded to free tier"
    end

    # Cancel membership (keeps account, sets status)
    def cancel_membership
      @member.cancel!
      redirect_to admin_member_path(@member), notice: "Membership cancelled"
    end

    # Reactivate cancelled membership
    def reactivate_membership
      @member.reactivate!
      redirect_to admin_member_path(@member), notice: "Membership reactivated"
    end

    # ── Bulk actions ─────────────────────────────────────────────────────────
    # Selection happens client-side (bulk_select_controller.js); these receive
    # the chosen ids. Deliberately NOT the file-oriented BulkContentActions
    # concern — members are DB records with their own delete rules (erase vs
    # anonymise) and member-specific actions (tier, newsletter).

    # Delete each selected member by the same rule as single delete: erase the
    # ones with nothing behind them, anonymise the rest (Member#anonymize!), so
    # payment/delivery history is never collaterally destroyed. Deleted-account
    # rows are skipped — there's nothing left to remove.
    def bulk_destroy
      erased = 0
      anonymized = 0
      Member.where(id: bulk_member_ids).find_each do |member|
        next if member.anonymized?
        if member.erasable?
          member.destroy
          erased += 1
        else
          member.anonymize!(by: :admin)
          anonymized += 1
        end
      end
      notice = "Deleted #{helpers.pluralize(erased + anonymized, 'member')}."
      notice += " #{anonymized} kept as anonymised records (they had payment or delivery history)." if anonymized.positive?
      redirect_to admin_members_path, notice: notice
    end

    # Set every selected member to one tier. The UI sends tier=free|paid; when
    # the selection is mixed it offers both buttons and each makes them all the
    # same. Downgrading clears the password digest (matches single downgrade);
    # upgrading needs a password, so generate one per member being upgraded.
    def bulk_set_tier
      tier = params[:tier].to_s
      return redirect_to(admin_members_path, alert: "Unknown tier.") unless %w[free paid].include?(tier)

      changed = 0
      Member.where(id: bulk_member_ids).find_each do |member|
        next if member.anonymized?
        if tier == "paid"
          next if member.tier_paid?
          member.upgrade_to_paid!(password: Member.generate_password)
        else
          next if member.tier_free?
          member.update!(tier: :free, password_digest: nil)
        end
        changed += 1
      end
      redirect_to admin_members_path, notice: "Changed #{helpers.pluralize(changed, 'member')} to #{tier}."
    end

    # Subscribe / unsubscribe the selected members. Only reachable when
    # newsletters are enabled (the UI hides it otherwise); re-checked here. A
    # bounced address can't be resubscribed — delivery is broken, not consent —
    # so those are skipped on subscribe.
    def bulk_newsletter
      return redirect_to(admin_members_path, alert: "Newsletters aren't enabled.") unless SiteFeature.newsletters_feature_enabled?
      action = params[:newsletter].to_s
      return redirect_to(admin_members_path, alert: "Unknown action.") unless %w[subscribe unsubscribe].include?(action)

      changed = 0
      skipped_bounced = 0
      Member.where(id: bulk_member_ids).find_each do |member|
        next if member.anonymized?
        if action == "subscribe"
          if member.newsletter_status_bounced?
            skipped_bounced += 1
            next
          end
          member.resubscribe_to_newsletter!
        else
          member.unsubscribe_from_newsletter!
        end
        changed += 1
      end
      notice = "#{action == 'subscribe' ? 'Subscribed' : 'Unsubscribed'} #{helpers.pluralize(changed, 'member')}."
      notice += " Skipped #{skipped_bounced} with a bounced address." if skipped_bounced.positive?
      redirect_to admin_members_path, notice: notice
    end

    # Permanently delete already-deleted (anonymised) accounts — the record and
    # EVERYTHING under it: donations, delivery history, recovery codes. This is
    # the irreversible purge, distinct from bulk_destroy (which anonymises).
    #
    # Refuses any member that isn't already anonymised: you purge a tombstone,
    # never a live member. Donations have a foreign key and no dependent:, so a
    # plain destroy would raise — they're destroyed explicitly first.
    def bulk_purge
      purged = 0
      skipped = 0
      Member.where(id: bulk_member_ids).find_each do |member|
        unless member.anonymized?
          skipped += 1
          next
        end
        Member.transaction do
          member.donations.destroy_all # FK-protected, no cascade — must go first
          member.destroy               # newsletter_sends + recovery codes cascade
        end
        purged += 1
      end
      notice = "Permanently deleted #{helpers.pluralize(purged, 'account')} and all their records."
      notice += " Skipped #{skipped} that weren't already deleted." if skipped.positive?
      redirect_to admin_members_path(status: "deleted"), notice: notice
    end

    private

    def bulk_member_ids
      Array(params[:ids]).flatten.map(&:to_s).select { |s| s.match?(/\A\d+\z/) }
    end

    def set_member
      @member = Member.find(params[:id])
    end

    def reject_deleted_account
      return unless @member.anonymized?

      # Non-GET refusals redirect with 303 — see ApplicationController#redirect_to,
      # which applies it to every such redirect rather than this one alone.
      redirect_to admin_member_path(@member),
        alert: "This account was deleted. Its payment and newsletter records are kept, but the account itself can't be changed."
    end

    def member_params
      params.require(:member).permit(:email, :name, :tier, :status, :password, :password_confirmation)
    end
  end
end
