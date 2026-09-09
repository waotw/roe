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

    private

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
