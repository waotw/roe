# frozen_string_literal: true

# Single source of truth for the ACTION builder — the editor modal that inserts
# `button` and `form` roe-anji blocks. Both blocks pick their kind with a `for:`
# line (see HasMarkdownExtensions#roeanji_kind); each field here maps 1:1 to a
# config key the matching renderer reads (render_share_button, render_form, …).
#
# Two axes: the block (button/form, chosen from the ACTION ▼ menu) and the kind
# (`for:` value, chosen in the modal). Kinds are globally unique across both
# blocks, so a field group is keyed by kind alone.
#
# Field shape mirrors CardBuilderSchema: key, type (:text / :textarea /
# :select), label, hint, and (for :select) options. No kind has strictly
# required fields — a bare block works via the renderer's defaults.
module ActionBuilderSchema
  # Button kinds (`for:` on a ```button block). `product` is the default a bare
  # button falls back to, so the builder omits its `for:` line on insert.
  BUTTON_KINDS = [
    { value: "product",   label: "Product",   feature: :store },
    { value: "share",     label: "Share",     feature: nil },
    { value: "subscribe", label: "Subscribe", feature: :members }
  ].freeze

  # Form kinds (`for:` on a ```form block). Membership flows gate on members;
  # the paywall needs payments (it's the upgrade-to-paid block).
  FORM_KINDS = [
    { value: "signup",       label: "Sign up",     feature: :members },
    { value: "signin",       label: "Sign in",     feature: :members },
    { value: "checkout",     label: "Checkout",    feature: :members },
    { value: "donate",       label: "Donate",      feature: :members },
    { value: "unsubscribe",  label: "Unsubscribe", feature: :members },
    # A paywall marks where the free part of an article ends — a content
    # structure, not a transaction. Writing one before Stripe is connected is
    # reasonable and useful; the upgrade button it renders is what needs keys,
    # and the block warns about that itself.
    #
    # It was the only kind here requiring working Stripe keys — Checkout and
    # Donate, which do take money, ask only for :members. So the one that
    # needed them least was the one gated hardest.
    { value: "paid_content", label: "Paywall",     feature: :payments_configured }
  ].freeze

  FIELDS_BY_KIND = {
    # --- buttons ---
    "product" => [
      { key: "sku", type: :text, label: "SKU",
        hint: "Product SKU. Auto-detected on a product page — leave blank there." },
      { key: "text", type: :text, label: "Button text",
        hint: "Defaults to “Add to Cart”." },
      { key: "style", type: :select, label: "Style", options: %w[primary secondary outline],
        hint: "Defaults to primary." },
      { key: "quantity", type: :text, label: "Quantity",
        hint: "Defaults to 1." },
      { key: "show_price", type: :select, label: "Show price", options: %w[true false],
        hint: "Show the price next to the button. On by default — set false to hide it. A variant list always shows its prices." }
    ],
    "share" => [
      { key: "label", type: :text, label: "Label",
        hint: "Trigger text. Defaults to “Share”." },
      { key: "url", type: :text, label: "URL",
        hint: "What to share. Defaults to the page's canonical URL." },
      { key: "title", type: :text, label: "Title",
        hint: "Defaults to the page's title." },
      { key: "text", type: :text, label: "Text",
        hint: "Extra text passed to the native share sheet." },
      { key: "style", type: :text, label: "Style",
        hint: "Theme style tokens, e.g. “small center”." }
    ],
    "subscribe" => [
      { key: "label", type: :text, label: "Label",
        hint: "Button text. Defaults to “Subscribe”." },
      { key: "url", type: :text, label: "URL",
        hint: "Link target. Defaults to /sign-up." },
      { key: "style", type: :text, label: "Style",
        hint: "Theme style tokens." }
    ],

    # --- forms ---
    "signup" => [
      { key: "button-text", type: :text, label: "Button text",
        hint: "Defaults to “Sign Up”." },
      { key: "upgrade-button-text", type: :text, label: "Upgrade button text",
        hint: "Adds a second button that signs up and goes straight to paid checkout. Only shows when payments are on." }
    ],
    "signin" => [
      { key: "button-text", type: :text, label: "Button text",
        hint: "Defaults to “Send Magic Link”." }
    ],
    "checkout" => [
      { key: "member-button-text", type: :text, label: "Member button text",
        hint: "Shown to logged-in members." },
      { key: "non-member-button-text", type: :text, label: "Non-member button text",
        hint: "Shown to non-members (links to sign-up)." }
    ],
    "donate" => [
      { key: "button-text", type: :text, label: "Button text",
        hint: "Defaults to “Donate”. Uses donation amounts from members.yml." }
    ],
    "unsubscribe" => [
      { key: "button-text", type: :text, label: "Button text",
        hint: "Defaults to “Unsubscribe”." }
    ],
    "paid_content" => [
      { key: "text", type: :textarea, label: "Message",
        hint: "Shown above the upgrade button." },
      { key: "button-text", type: :text, label: "Button text",
        hint: "Defaults to “Become a paid member”." }
    ]
  }.freeze

  # Button kinds available given the enabled features (share is always on).
  def self.button_kinds(store:, members:)
    BUTTON_KINDS.select { |k| feature_on?(k[:feature], store: store, members: members) }
  end

  # Form kinds available given the enabled features.
  #
  # payments: Stripe is connected and can charge — for the kinds that take
  #   money.
  # payments_configured: members.yml turns payments on, whatever Stripe's
  #   state — for the paywall, which only marks a boundary in the writing.
  def self.form_kinds(members:, payments:, payments_configured: payments)
    FORM_KINDS.select do |k|
      feature_on?(k[:feature], members: members, payments: payments,
                               payments_configured: payments_configured)
    end
  end

  def self.fields_for(kind)
    FIELDS_BY_KIND[kind] || []
  end

  def self.feature_on?(feature, store: false, members: false, payments: false,
                       payments_configured: payments)
    case feature
    when :store               then store
    when :members             then members
    when :payments            then payments
    when :payments_configured then payments_configured
    else true
    end
  end
end
