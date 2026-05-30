# Ships an Import's locally-created Members and NewsletterSends to live,
# in batched HTTP POSTs through SiteSync::Exchange. Used after a Substack
# import is fully complete (phases 1–4) — the file-based content (posts,
# pages, media) has already been pushed via site sync, and now this job
# pushes the DB-only side.
#
# Status is tracked in a per-import cache key so the imports/show panel
# can poll progress (similar pattern to SiteSyncTransferJob). Idempotency
# lives on the receiver: re-running this job is safe — the receiver
# skips members by email and sends by [post_id, member_id].
#
# Errors bubble up so Solid Queue marks the job failed. The cache status
# captures whatever counts we accumulated before the failure so the UI
# can show "got 4 batches in before the network blip; re-run to finish."
class ImportPublishJob < ApplicationJob
  queue_as :default

  STATUS_TTL = 1.day
  BATCH_SIZE = 1000

  STEPS = {
    starting:           "Starting…",
    publishing_members: "Publishing members…",
    publishing_sends:   "Publishing newsletter deliveries…"
  }.freeze

  def self.status_cache_key(import_id)
    "import:#{import_id}:publish_status"
  end

  def perform(import_id)
    @import     = Import.find(import_id)
    @started_at = Time.current
    @counts = {
      members_inserted: 0, members_skipped: 0,
      sends_inserted:   0, sends_skipped:   0,
      sends_no_post:    0, sends_no_member: 0
    }
    @errors = []

    update_step(:starting)

    publish_members!
    publish_sends!

    completed_at = Time.current
    write_status(
      state:        :completed,
      started_at:   @started_at,
      completed_at: completed_at,
      counts:       @counts,
      errors:       @errors.first(50)
    )

    # Persist the outcome on the Import record itself so the publish
    # panel can display "published on X" indefinitely — the cache
    # entry above is transient (1-day TTL) and a stale cache miss
    # shouldn't make the panel re-suggest a publish that already
    # happened. Stringify everything since stats is serialized to JSON.
    @import.stats = (@import.stats || {}).merge(
      "published_to_live" => {
        "at"     => completed_at.iso8601,
        "counts" => @counts.transform_keys(&:to_s),
        "errors" => @errors.first(50)
      }
    )
    @import.save!
  rescue => e
    Rails.logger.error "[ImportPublishJob #{import_id}] #{e.class}: #{e.message}"
    write_status(
      state:      :failed,
      step:       @last_step,
      started_at: @started_at,
      failed_at:  Time.current,
      error:      e.message,
      counts:     @counts,
      errors:     @errors.first(50)
    )
    raise
  end

  private

  def publish_members!
    update_step(:publishing_members)
    scope = Member.where(import: @import)
    total = scope.count
    @counts[:members_total] = total
    return if total.zero?

    scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      result = SiteSync::Exchange.publish_members(serialize_members(batch))
      raise "publish_members batch failed (network/auth/peer error)" unless result

      @counts[:members_inserted] += result["inserted"].to_i
      @counts[:members_skipped]  += result["skipped"].to_i
      @errors.concat(Array(result["errors"]))

      update_step(:publishing_members)
    end
  end

  def publish_sends!
    update_step(:publishing_sends)
    scope = NewsletterSend.where(import: @import).includes(:post, :member)
    total = scope.count
    @counts[:sends_total] = total
    return if total.zero?

    scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      payload = serialize_sends(batch)
      next if payload.empty?

      result = SiteSync::Exchange.publish_newsletter_sends(payload)
      raise "publish_newsletter_sends batch failed (network/auth/peer error)" unless result

      @counts[:sends_inserted]  += result["inserted"].to_i
      @counts[:sends_skipped]   += result["skipped"].to_i
      @counts[:sends_no_post]   += result["no_post"].to_i
      @counts[:sends_no_member] += result["no_member"].to_i
      @errors.concat(Array(result["errors"]))

      update_step(:publishing_sends)
    end
  end

  # All fields the receiver accepts. Strip-list lives on the receiver
  # (id, access_token, etc.) — sending more than needed is harmless,
  # but we keep the wire payload tight by sending exactly what's used.
  def serialize_members(batch)
    batch.map do |m|
      {
        email:                      m.email,
        name:                       m.name,
        metadata:                   m.metadata,
        status:                     m.status,
        tier:                       m.tier,
        newsletter_status:          m.newsletter_status,
        created_at:                 m.created_at&.iso8601,
        updated_at:                 m.updated_at&.iso8601,
        subscribed_at:              m.subscribed_at&.iso8601,
        cancelled_at:               m.cancelled_at&.iso8601,
        paid_at:                    m.paid_at&.iso8601,
        paid_amount_cents:          m.paid_amount_cents,
        paid_currency:              m.paid_currency,
        refunded_at:                m.refunded_at&.iso8601,
        refunded_amount_cents:      m.refunded_amount_cents,
        refunded_currency:          m.refunded_currency,
        email_confirmation_sent_at: m.email_confirmation_sent_at&.iso8601,
        pending_email:              m.pending_email
      }
    end
  end

  # Newsletter sends reference posts by natural key (substack_post_id
  # first, url_name fallback) and members by email. Skip any send
  # whose post or member has been deleted locally — there's nothing
  # useful to publish about an orphaned delivery row.
  def serialize_sends(batch)
    batch.filter_map do |s|
      next unless s.post && s.member
      {
        substack_post_id: s.post.metadata&.dig("substack_post_id"),
        url_name:         s.post.metadata&.dig("url_name") || s.post.try(:url_name),
        member_email:     s.member.email,
        message_id:       s.message_id,
        sent_at:          s.sent_at&.iso8601,
        created_at:       s.created_at&.iso8601,
        updated_at:       s.updated_at&.iso8601
      }
    end
  end

  def update_step(step)
    @last_step = step
    Rails.logger.info "[ImportPublishJob #{@import.id}] step: #{step}"
    write_status(
      state:      :running,
      step:       step,
      started_at: @started_at,
      counts:     @counts
    )
  end

  def write_status(data)
    Rails.cache.write(self.class.status_cache_key(@import.id), data, expires_in: STATUS_TTL)
  end
end
