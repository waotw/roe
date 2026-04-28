# Payments & Stripe

Roe integrates with Stripe for paid memberships, subscriptions, and one-time donations. The architecture separates payment logic from member management through the `StripeProductManager` service.

## Architecture Overview

```
Checkout Request
      │
      ▼
┌────────────────────────────────────┐
│   CheckoutController               │
│   (members/checkout)               │
│                                    │
│  • Create checkout session         │
│  • Handle success/cancel           │
└──────────────┬─────────────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
┌──────────┐     ┌──────────────┐
│  Stripe  │     │   Member     │
│ Checkout │     │   Model      │
│ Session  │     │              │
└────┬─────┘     └──────┬───────┘
     │                  │
     │ Webhook          │ upgrade_to_paid!
     ▼                  ▼
┌──────────────────────────────┐
│   WebhooksController         │
│   (stripe webhooks)          │
│                              │
│  • checkout.completed        │
│  • invoice.payment_failed    │
│  • customer.subscription.    │
│    deleted                   │
└──────────────────────────────┘
```

**Graph Note:** Payment & Email Integration is a core community (21 nodes) connecting Stripe, Postmark, and member lifecycle management.

## Stripe Configuration

File: `app/models/stripe_config.rb`

### Configuration Storage

```yaml
# site/system/features/stripe.yml
api_key: sk_live_...          # Encrypted at rest
webhook_secret: whsec_...     # For webhook verification
price_id: price_...           # Default subscription price
product_id: prod_...          # Stripe product ID
currency: usd                 # 3-letter ISO code
```

### Encryption

Sensitive fields are encrypted using Rails encryption:

```ruby
class StripeConfig
  encrypts :api_key, :webhook_secret
end
```

**Important:** Never commit unencrypted API keys to version control.

## StripeProductManager Service

File: `app/services/stripe_product_manager.rb`

Central service for all Stripe interactions:

### Key Methods

```ruby
# Create/update Stripe product from local Product model
def sync_product(product)
  # Creates Stripe product + price
  # Stores stripe_product_id on local model
end

# Get or create Stripe customer for member
def find_or_create_customer(member)
  # Returns Stripe::Customer
  # Stores stripe_customer_id on member
end

# Create checkout session
def create_checkout_session(member, product:, success_url:, cancel_url:)
  # Returns Stripe::Checkout::Session
end

# Cancel subscription
def cancel_subscription(member)
  # Cancels at period end
end

# Reactivate subscription
def reactivate_subscription(member)
  # Removes cancellation date
end
```

## Checkout Flow

### 1. Initiate Checkout

```ruby
# Members::CheckoutController#create
def create
  @member = current_member || Member.create!(email: params[:email])
  
  session = StripeProductManager.create_checkout_session(
    @member,
    product: Product.find(params[:product_id]),
    success_url: success_members_checkout_url,
    cancel_url: cancel_members_checkout_url
  )
  
  redirect_to session.url, allow_other_host: true
end
```

### 2. Success Handling

```ruby
# Members::CheckoutController#success
def success
  # Stripe redirects here after payment
  # Member is already updated via webhook
  redirect_to account_path, notice: "Welcome! Your subscription is active."
end
```

### 3. Webhook Processing

```ruby
# WebhooksController#stripe
def stripe
  event = construct_stripe_event
  
  case event['type']
  when 'checkout.session.completed'
    handle_checkout_completed(event)
  when 'invoice.payment_failed'
    handle_payment_failed(event)
  when 'customer.subscription.deleted'
    handle_subscription_cancelled(event)
  end
  
  head :ok
end
```

## Webhook Events

### checkout.session.completed

Triggered when checkout succeeds:

```ruby
def handle_checkout_completed(event)
  session = event['data']['object']
  member = Member.find_by(stripe_customer_id: session['customer'])
  
  member.upgrade_to_paid_with_stripe!(
    subscription_id: session['subscription'],
    customer_id: session['customer']
  )
  
  MemberMailer.upgrade_success(member).deliver_later
end
```

### invoice.payment_failed

Triggered when subscription payment fails:

```ruby
def handle_payment_failed(event)
  invoice = event['data']['object']
  member = Member.find_by(stripe_customer_id: invoice['customer'])
  
  MemberMailer.payment_failed(member).deliver_later
end
```

### customer.subscription.deleted

Triggered when subscription ends:

```ruby
def handle_subscription_cancelled(event)
  subscription = event['data']['object']
  member = Member.find_by(stripe_subscription_id: subscription['id'])
  
  member.cancel!  # Marks as cancelled, removes subscription_id
end
```

## Subscription Lifecycle

```
Free Member
     │
     │ Checkout
     ▼
┌─────────────┐
│   Active    │
│   (Paid)    │
└──────┬──────┘
       │
   ┌───┴───┐
   │       │
Cancel   Payment
 │        Fails
 ▼          │
Pending    ▼
Cancel  Past Due
  │        │
  │      Retry
  │        │
  │     Success
  │        │
  │        ▼
  │    Active
  │
  ▼
Cancelled
(Free)
```

## Member Model Integration

### Upgrade to Paid

```ruby
# app/models/member.rb

def upgrade_to_paid_with_stripe!(stripe_data)
  update!(
    stripe_customer_id: stripe_data[:customer_id],
    stripe_subscription_id: stripe_data[:subscription_id],
    subscribed_at: Time.current,
    subscription_status: 'active'
  )
end
```

### Cancel

```ruby
def cancel!
  update!(
    subscription_status: 'cancelled',
    stripe_subscription_id: nil
  )
end
```

### Reactivate

```ruby
def reactivate!
  update!(subscription_status: 'active')
  # Note: If past grace period, needs new checkout
end
```

## Donations

One-time donations use the same checkout flow but with `payment` mode instead of `subscription`:

```ruby
# DonationsController
def create
  session = Stripe::Checkout::Session.create(
    mode: 'payment',  # One-time, not subscription
    line_items: [{
      price_data: {
        currency: 'usd',
        unit_amount: params[:amount_cents],
        product_data: { name: 'Donation' }
      },
      quantity: 1
    }],
    success_url: success_url,
    cancel_url: cancel_url
  )
  
  redirect_to session.url, allow_other_host: true
end
```

## Admin Configuration

### Connecting Stripe

1. Go to **Admin → Config → Payments**
2. Enter Stripe API keys (test or live)
3. Configure webhook endpoint: `https://yoursite.com/webhooks/stripe`
4. Copy webhook secret to config
5. Create product/price in Stripe or use auto-sync

### Auto-Sync Products

When you create a `Product` in Roe, it can auto-sync to Stripe:

```ruby
# app/models/product.rb
after_save :sync_to_stripe, if: :paid?

def sync_to_stripe
  StripeProductManager.sync_product(self)
end
```

### Webhook Endpoint Setup

In Stripe Dashboard:

1. Developers → Webhooks → Add endpoint
2. URL: `https://yoursite.com/webhooks/stripe`
3. Events to listen to:
   - `checkout.session.completed`
   - `invoice.payment_failed`
   - `customer.subscription.deleted`
   - `customer.subscription.updated`

## Currency Handling

### Default Currency

Set in `site/system/global/site.yml`:

```yaml
store_currency: USD
```

Or fetch from Stripe account:

```ruby
# StripeConfig.fetch_currency!
def fetch_currency!
  account = Stripe::Account.retrieve
  update!(currency: account.default_currency)
end
```

### Display Formatting

Use the helper for consistent currency display:

```erb
<%= format_currency(1000) %>  # $10.00
<%= format_currency(1000, 'EUR') %>  # €10.00
```

## Testing

### Test Mode

Always use Stripe test keys in development:

```yaml
# Development
development:
  api_key: sk_test_...
  webhook_secret: whsec_test_...
  price_id: price_test_...
```

### Test Cards

| Card Number | Result |
|-------------|--------|
| `4242 4242 4242 4242` | Success |
| `4000 0000 0000 0002` | Declined |
| `4000 0000 0000 0341` | Authentication required |

### Webhook Testing

Use Stripe CLI for local webhook testing:

```bash
stripe listen --forward-to localhost:3000/webhooks/stripe
```

## Security

### Webhook Verification

Always verify webhook signatures:

```ruby
def construct_stripe_event
  payload = request.body.read
  sig_header = request.env['HTTP_STRIPE_SIGNATURE']
  
  Stripe::Webhook.construct_event(
    payload, sig_header, StripeConfig.current.webhook_secret
  )
rescue JSON::ParserError, Stripe::SignatureVerificationError
  head :bad_request
end
```

### API Key Protection

- Store keys encrypted in database
- Use environment variables for initial config
- Rotate keys regularly
- Never log API keys

## Troubleshooting

### Common Issues

**Webhook not received:**
- Check webhook URL is publicly accessible
- Verify webhook secret matches
- Check Stripe dashboard for failed deliveries

**Payment succeeds but member not upgraded:**
- Check webhook is processing without errors
- Verify `checkout.session.completed` handler
- Check Rails logs for exceptions

**Member can't access paid content after payment:**
- Verify `subscribed_at` is set
- Check `subscription_status` is 'active'
- Clear cache if using fragment caching

## Related

- [Members & Authentication](./11-members-authentication.md) - Member model and access control
- [Products & Store](./16-products-store.md) - Product catalog and Snipcart
- [Configuration](./06-configuration.md) - site.yml and feature flags
- [Routes](./08-routes.md) - Checkout and webhook routes
