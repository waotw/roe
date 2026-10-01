class SnipcartOrder < ApplicationRecord
  # Snipcart has no read/management API, so every order Roe knows about arrives
  # by webhook and is stored here. See Webhooks::SnipcartController.

  # Test vs. live, from the webhook payload's `mode`. Lets the Orders page show
  # test orders only while Roe/Snipcart is in test mode, and real orders in live.
  enum :mode, { test: 0, live: 1 }, prefix: true

  scope :recent, -> { order(placed_at: :desc, created_at: :desc) }
  scope :refunded, -> { where.not(refunded_at: nil) }

  # Orders for a given mode string ("test"/"live"), tolerating nil/unknown by
  # returning none so a caller never accidentally shows the wrong mode's orders.
  scope :for_mode, ->(m) { where(mode: modes[m.to_s]) if modes.key?(m.to_s) }

  # The Roe member who placed this order, matched by email (case-insensitive) —
  # the one link Snipcart can't make itself. Not a stored foreign key: matching
  # at read time means a member who signs up AFTER buying is badged on their
  # past orders too. (Not memoised: a single render calls this at most twice,
  # and memoising would go stale across a reload in tests/long-lived objects.)
  def member
    return nil if email.blank?
    Member.find_by("LOWER(email) = ?", email.downcase)
  end

  def member? = member.present?

  def total
    return nil if total_cents.nil?
    total_cents / 100.0
  end

  def refunded?
    refunded_at.present?
  end

  # ── Line items (read from the stored raw payload) ──────────────────────────
  #
  # Snipcart nests purchased items under content["items"], each a hash with
  # "name", "id" (the SKU/data-item-id), "url", "price", "quantity". We stored
  # the whole payload, so read them here rather than modelling separate rows.
  # Returns [] for an order with no captured items (e.g. a bare refund row).
  Item = Struct.new(:name, :sku, :url, :quantity, keyword_init: true)

  def items
    Array(payload["items"]).filter_map do |i|
      next unless i.is_a?(Hash)
      Item.new(
        name:     i["name"].presence,
        sku:      i["id"].presence,
        url:      i["url"].presence,
        quantity: i["quantity"]
      )
    end
  end

  # A one-line "what they bought" for the index: the SKU of the first item (most
  # orders are a single item), with a "+N more" when there are several. nil when
  # no items were captured.
  def sku_summary
    list = items
    return nil if list.empty?

    first = list.first.sku || list.first.name
    return nil if first.blank?

    list.size > 1 ? "#{first} +#{list.size - 1} more" : first
  end

  # ── Ingest from a Snipcart webhook payload ────────────────────────────────
  #
  # Upsert by snipcart_token so a webhook retry (Snipcart re-sends on non-2xx)
  # updates the same row rather than duplicating. `content` is the order object
  # Snipcart nests under the webhook envelope; `mode` is "test"/"live" from the
  # envelope.
  def self.record_completed!(content, mode: "test")
    token = content["token"].presence or return nil

    order = find_or_initialize_by(snipcart_token: token)
    order.assign_attributes(
      mode:        normalize_mode(mode),
      email:       content["email"],
      name:        content.dig("billingAddress", "fullName").presence || content["cardHolderName"],
      total_cents: cents(content["finalGrandTotal"] || content["total"]),
      currency:    content["currency"],
      status:      content["status"],
      placed_at:   parse_time(content["completionDate"] || content["creationDate"]),
      payload:     sanitize_payload(content)
    )
    order.save!
    order
  end

  # A refund event references an existing order by token; stamp the refund
  # fields and keep the latest payload. If we never saw the order (webhook
  # ordering, or refund of a pre-Roe order), create a minimal row so the
  # refund still shows.
  def self.record_refund!(content, mode: "test")
    token = content["token"].presence or return nil

    order = find_or_initialize_by(snipcart_token: token)
    order.mode          = normalize_mode(mode) if order.new_record?
    order.email       ||= content["email"]
    order.currency    ||= content["currency"]
    order.total_cents ||= cents(content["finalGrandTotal"] || content["total"])
    order.assign_attributes(
      refunded_amount_cents: cents(content["refundsAmount"] || content["totalRefunded"]),
      refunded_currency:     content["currency"],
      refunded_at:           parse_time(content["modificationDate"]) || Time.current,
      status:                content["status"] || order.status,
      payload:               sanitize_payload(content)
    )
    order.save!
    order
  end

  # Strip purchaser address/phone data before persisting the payload. Roe never
  # uses it (Snipcart owns fulfillment), and not holding it is stronger than
  # hiding it: nothing to leak in a backup, export, or breach. We keep the whole
  # payload otherwise (line items, totals, tokens) for future features. Applied
  # on ingest, so the DB never sees the removed fields. Recursive so nested or
  # future address/phone-shaped keys are caught too.
  REDACTED_KEYS = %w[
    billingaddress shippingaddress address address1 address2 fulladdress
    phone phonenumber
  ].freeze

  def self.sanitize_payload(node)
    case node
    when Hash
      node.each_with_object({}) do |(k, v), out|
        next if REDACTED_KEYS.include?(k.to_s.downcase.delete("_-"))
        out[k] = sanitize_payload(v)
      end
    when Array
      node.map { |v| sanitize_payload(v) }
    else
      node
    end
  end

  def self.normalize_mode(mode)
    modes.key?(mode.to_s) ? mode.to_s : "test"
  end

  def self.cents(amount)
    return nil if amount.nil?
    (amount.to_f * 100).round
  end

  def self.parse_time(value)
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
