# frozen_string_literal: true

module SiteSync
  # Applies a batch of imported members to this side, for the publish step at
  # the end of a Substack import.
  #
  # This used to be skip-if-exists, which made the last step of the obvious
  # workflow do nothing: import, keep using Substack for a while, then run a
  # final import before launch. Every member already here was skipped, so tier
  # grants added since the first import never landed. The panel reported it
  # honestly — "0 inserted, N already on live" — and it read like success.
  #
  # Updating in place rather than clearing and re-publishing: the batch IS the
  # list of people to touch, so nothing has to identify which import a member
  # came from, and newsletter_sends are never destroyed and re-created (they
  # are what stops Roe re-sending Substack's own archive).
  #
  # Three rules, all the same shape — an import may add, never take away:
  #
  #   1. Tier is never lowered. A lapsed annual comes back from the importer
  #      as `free`, and applying that would revoke access someone already has.
  #      Reported instead, for the owner to decide.
  #   2. Consent is never restored. Unsubscribed here stays unsubscribed, even
  #      if the CSV still lists them as subscribed.
  #   3. A deleted account is never updated — as far as it can tell.
  #
  # That last one has a limit worth stating. anonymize! replaces the address,
  # and email is the only key, so a member who deleted their own account and is
  # still listed in a later CSV arrives looking like somebody new, and gets
  # imported. Roe can't recognise them, because recognising them would mean
  # keeping a fingerprint of the address it just promised to destroy — and that
  # would also stop someone who deleted their account from ever signing up
  # again. Deliberate: the CSV is treated as current intent, and the owner
  # removes anyone it shouldn't have carried over.
  #
  # Members marked deleted from the admin form keep their address, so those ARE
  # recognised and left alone.
  #
  # Anything with its own history on this side is left alone entirely and
  # reported, so the owner can finish those by hand.
  class MemberPublish
    # Set by real activity on this side, never by an import — so any one of
    # them means a person did something here that a CSV shouldn't overwrite.
    # Deliberately NOT password_digest: members sign in by emailed link, so
    # its presence and its absence both prove nothing.
    ACTIVITY_FIELDS = %w[stripe_customer_id stripe_payment_intent_id cancelled_at pending_email].freeze

    # Reasons a member in the batch wasn't applied. The owner acts on these
    # differently, so they're kept apart rather than pooled into "skipped".
    FOLLOW_UP_REASONS = %i[lapsed_paid has_activity deleted not_imported].freeze

    Result = Struct.new(:inserted, :updated, :skipped, :follow_up, :errors, keyword_init: true) do
      def to_h
        {
          inserted: inserted, updated: updated, skipped: skipped,
          follow_up: follow_up, errors: errors
        }
      end
    end

    def self.call(members) = new(members).call

    def initialize(members)
      @members  = Array(members)
      @inserted = 0
      @updated  = 0
      @skipped  = 0
      @errors   = []
      @follow_up = FOLLOW_UP_REASONS.index_with { [] }
    end

    def call
      @members.each { |attrs| apply(attrs) }

      Result.new(
        inserted: @inserted, updated: @updated, skipped: @skipped,
        follow_up: @follow_up.transform_keys(&:to_s), errors: @errors
      )
    end

    private

    def apply(attrs)
      email = attrs["email"].to_s.strip
      return @errors << "blank email skipped" if email.blank?

      existing = Member.find_by(email: email)
      return insert(attrs) if existing.nil?
      return note(:deleted, email) if existing.status_deleted?
      return note(:not_imported, email) unless imported?(existing)
      return note(:has_activity, email) if activity?(existing)

      update(existing, email, attrs)
    rescue StandardError => e
      @errors << "#{attrs['email']}: #{e.class} #{e.message}"
    end

    def insert(attrs)
      Member.create!(member_attrs(attrs))
      @inserted += 1
    end

    def update(member, email, attrs)
      incoming = member_attrs(attrs)

      # Live keeps its own. member_attrs_from copies the sender's timestamps,
      # and overwriting this would scramble "member since" on every republish.
      incoming.delete(:created_at)

      if member.tier_paid? && incoming[:tier].to_s == "free"
        incoming[:tier] = member.tier
        note(:lapsed_paid, email, counted: false)
      end

      incoming[:newsletter_status] = member.newsletter_status unless member.newsletter_status_subscribed?

      member.update!(incoming)
      @updated += 1
    end

    def imported?(member)
      member.metadata.is_a?(Hash) && member.metadata["substack_imported"].present?
    end

    def activity?(member)
      ACTIVITY_FIELDS.any? { |field| member.public_send(field).present? }
    end

    # counted: false for a member who WAS applied and just has something worth
    # mentioning — a lapsed subscription whose tier we deliberately left alone.
    # Counting those as skipped would claim nothing happened, when most of the
    # record did update.
    def note(reason, email, counted: true)
      @follow_up[reason] << email
      @skipped += 1 if counted
      nil
    end

# The whitelist of fields accepted from the sender. Stripped, and why:
#   - id / import_id   PKs and FKs don't survive crossing databases
#   - access_token     unique-indexed; this side mints its own on create
#   - media_token      same
#   - password_digest, email_confirmation_token
#                      auth state that doesn't belong to an imported member
#   - stripe_customer_id / stripe_payment_intent_id
#                      point at the sender's test Stripe customers
#
# Lived on the controller until this class took over applying them; one
# copy, so the shape accepted and the shape written can't drift apart.
    def member_attrs(attrs)
      {
        email:                       attrs["email"].to_s.strip,
        name:                        attrs["name"],
        metadata:                    attrs["metadata"] || {},
        status:                      attrs["status"],
        tier:                        attrs["tier"],
        newsletter_status:           attrs["newsletter_status"],
        created_at:                  attrs["created_at"],
        updated_at:                  attrs["updated_at"],
        subscribed_at:               attrs["subscribed_at"],
        cancelled_at:                attrs["cancelled_at"],
        paid_at:                     attrs["paid_at"],
        paid_amount_cents:           attrs["paid_amount_cents"],
        paid_currency:               attrs["paid_currency"],
        refunded_at:                 attrs["refunded_at"],
        refunded_amount_cents:       attrs["refunded_amount_cents"],
        refunded_currency:           attrs["refunded_currency"],
        email_confirmation_sent_at:  attrs["email_confirmation_sent_at"],
        pending_email:               attrs["pending_email"]
      }
    end
  end
end
