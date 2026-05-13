module Api
  module SiteSync
    # Receives imported data (members + newsletter sends) published from
    # the dev side after a Substack import. The import itself runs only
    # in development (dev-only feature); this endpoint exists on live to
    # receive the results. Auth via shared SyncConfig token, same as the
    # rest of /api/site_sync.
    #
    # Idempotency policy is skip-if-exists across the board:
    #   - Members keyed by email (unique index)
    #   - Newsletter sends keyed by [post_id, member_id] (unique index)
    #
    # Posts are NOT shipped here — they arrive via the file-based site
    # sync (rsync). Newsletter sends reference posts by their natural
    # key from the Substack import (substack_post_id in metadata), with
    # url_name as a fallback for posts without a Substack origin.
    class ImportsController < BaseController
      # POST /api/site_sync/publish_members
      # Body:    { members: [ {email, name, metadata, status, tier, ...}, ... ] }
      # Returns: { inserted, skipped, errors: [...] }
      def publish_members
        payload = JSON.parse(request.body.read)
        members = Array(payload['members'])

        inserted = 0
        skipped  = 0
        errors   = []

        members.each do |attrs|
          email = attrs['email'].to_s.strip
          if email.blank?
            errors << "blank email skipped"
            next
          end

          if Member.exists?(email: email)
            skipped += 1
            next
          end

          begin
            Member.create!(member_attrs_from(attrs))
            inserted += 1
          rescue => e
            errors << "#{email}: #{e.class} #{e.message}"
          end
        end

        render json: { inserted: inserted, skipped: skipped, errors: errors }
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error "[Api::SiteSync::ImportsController] publish_members FAILED: #{e.class} #{e.message}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      # POST /api/site_sync/publish_newsletter_sends
      # Body:    { sends: [ {substack_post_id, url_name, member_email, message_id, sent_at, ...}, ... ] }
      # Returns: { inserted, skipped, no_post, no_member, errors: [...] }
      #
      # Per-record outcomes:
      #   - inserted:   created a new NewsletterSend
      #   - skipped:    [post_id, member_id] already had a row (unique idx)
      #   - no_post:    couldn't resolve substack_post_id or url_name to a Post
      #                 (likely: site sync hasn't run yet, or post was deleted)
      #   - no_member:  couldn't find a Member with that email
      #                 (likely: publish_members hasn't run yet for them)
      def publish_newsletter_sends
        payload = JSON.parse(request.body.read)
        sends   = Array(payload['sends'])

        inserted  = 0
        skipped   = 0
        no_post   = 0
        no_member = 0
        errors    = []

        sends.each do |attrs|
          post = resolve_post(attrs)
          if post.nil?
            no_post += 1
            next
          end

          member = Member.find_by(email: attrs['member_email'].to_s.strip)
          if member.nil?
            no_member += 1
            next
          end

          if NewsletterSend.exists?(post_id: post.id, member_id: member.id)
            skipped += 1
            next
          end

          begin
            NewsletterSend.create!(
              post_id:    post.id,
              member_id:  member.id,
              message_id: attrs['message_id'],
              sent_at:    attrs['sent_at'],
              created_at: attrs['created_at'],
              updated_at: attrs['updated_at']
            )
            inserted += 1
          rescue => e
            errors << "#{attrs['member_email']}: #{e.class} #{e.message}"
          end
        end

        render json: {
          inserted:  inserted,
          skipped:   skipped,
          no_post:   no_post,
          no_member: no_member,
          errors:    errors
        }
      rescue JSON::ParserError => e
        render json: { error: "invalid json: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error "[Api::SiteSync::ImportsController] publish_newsletter_sends FAILED: #{e.class} #{e.message}"
        render json: { error: "#{e.class}: #{e.message}" }, status: :internal_server_error
      end

      private

      # Whitelist of fields we accept from the sender. Stripped:
      #   - id / import_id   (PKs and FKs don't survive cross-DB)
      #   - access_token     (unique-indexed; live regenerates via callback)
      #   - password_digest, email_confirmation_token (transient/auth state
      #     that doesn't belong to imported members)
      #   - stripe_customer_id / stripe_payment_intent_id (point at dev's
      #     test Stripe customers — meaningless on live)
      def member_attrs_from(attrs)
        {
          email:                       attrs['email'].to_s.strip,
          name:                        attrs['name'],
          metadata:                    attrs['metadata'] || {},
          status:                      attrs['status'],
          tier:                        attrs['tier'],
          newsletter_status:           attrs['newsletter_status'],
          created_at:                  attrs['created_at'],
          updated_at:                  attrs['updated_at'],
          subscribed_at:               attrs['subscribed_at'],
          cancelled_at:                attrs['cancelled_at'],
          paid_at:                     attrs['paid_at'],
          paid_amount_cents:           attrs['paid_amount_cents'],
          paid_currency:               attrs['paid_currency'],
          refunded_at:                 attrs['refunded_at'],
          refunded_amount_cents:       attrs['refunded_amount_cents'],
          refunded_currency:           attrs['refunded_currency'],
          email_confirmation_sent_at:  attrs['email_confirmation_sent_at'],
          pending_email:               attrs['pending_email']
        }
      end

      # Look up the target post. Tries substack_post_id first (most stable
      # — comes straight from Substack and is preserved in metadata),
      # then falls back to url_name for posts that weren't Substack-imported.
      def resolve_post(attrs)
        if attrs['substack_post_id'].present?
          post = Post.where(
            "json_extract(metadata, '$.substack_post_id') = ?",
            attrs['substack_post_id'].to_s
          ).first
          return post if post
        end

        if attrs['url_name'].present?
          Post.where(
            "json_extract(metadata, '$.url_name') = ?",
            attrs['url_name'].to_s
          ).first
        end
      end
    end
  end
end
