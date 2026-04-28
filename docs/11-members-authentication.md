# Members & Authentication

Roe uses magic-link authentication for members, eliminating passwords while supporting paid memberships, newsletters, and content gating.

## Architecture Overview

```
Member Request
      │
      ▼
┌──────────────────────────────────────┐
│   MemberAuthentication Concern       │
│   (controllers/concerns/)            │
│                                      │
│  • set_current_member (before_action)│
│  • current_member helper             │
│  • can_access_premium? check         │
└──────────────┬───────────────────────┘
               │
      ┌────────┴────────┐
      ▼                 ▼
┌──────────┐     ┌──────────────┐
│  Member  │     │   Current    │
│  Model   │     │   Attribute  │
│          │     │              │
│• email   │     │• member      │
│• token   │     │  (per-request)│
│• status  │     │              │
│• paid?   │     │              │
└──────────┘     └──────────────┘
```

**Graph Note:** The `Member` model is a bridge node connecting Member Management to Payment & Email Integration communities (25 edges in architecture graph).

## Member Model

File: `app/models/member.rb`

### Core Attributes

```ruby
# Authentication
email           # Unique identifier
token           # Magic link token (regenerated on each sign-in)
unsubscribe_token  # For newsletter unsubscribes

# Status
token_expires_at   # Magic link expiration
email_confirmed_at # When email was verified
subscribed_at      # When member joined

# Membership
stripe_customer_id     # Stripe reference
stripe_subscription_id # Active subscription
subscription_status    # active, cancelled, past_due
```

### Member States

| Status | Description |
|--------|-------------|
| `active?` | Token not expired, email confirmed |
| `paid?` | Has active Stripe subscription |
| `free?` | No active subscription |
| `cancelled?` | Subscription cancelled but still in grace period |
| `can_access?(post)` | Checks if member can access specific content |

### Key Methods

```ruby
# app/models/member.rb

# Generate new magic link token
generate_token!  # Creates token, sets 24hr expiration

# Confirm email address
confirm_email!(token)  # Validates confirmation token

# Subscription management
upgrade_to_paid!(stripe_data)
cancel!
reactivate!

# Access control
can_access?(post)  # Uses HasAudience concern
```

## Authentication Flow

### 1. Sign In (Magic Link Request)

```
User enters email
      │
      ▼
Members::SessionsController#create
      │
      ▼
Member.find_or_create_by(email:)
      │
      ▼
member.generate_token!
      │
      ▼
MemberMailer.magic_link(member).deliver
```

### 2. Magic Link Click

```
GET /members/sessions/new?token=abc123
      │
      ▼
Members::SessionsController#signin_with_token
      │
      ▼
Member.find_by(token: params[:token])
      │
      ▼
member.active?  # Check token not expired
      │
      ▼
session[:member_id] = member.id
      │
      ▼
Redirect to intended destination
```

### 3. Per-Request Authentication

Every request includes:

```ruby
# controllers/concerns/member_authentication.rb

before_action :set_current_member

private

def set_current_member
  Current.member = Member.find_by(id: session[:member_id])
end

def current_member
  Current.member
end
```

## Current Attribute

File: `app/models/current.rb`

The `Current` model provides thread-safe, per-request attributes:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :member
end
```

**Usage:** Access `Current.member` anywhere during the request:

```ruby
# In controllers, views, models, helpers
if Current.member&.paid?
  # Show premium content
end
```

**Graph Note:** `set_current_member()` and `current_member()` create edges from MemberAuthentication concern to Member model, bridging authentication and member data communities.

## Access Control & Content Gating

### HasAudience Concern

File: `app/models/concerns/has_audience.rb`

Content types (Post, Page, Product) use `HasAudience` for access control:

```ruby
class Post
  include HasAudience
end
```

### Audience Types

| Audience | Access Rule |
|----------|-------------|
| `public` | Anyone can view |
| `free` | Free members only (must be authenticated) |
| `paid` | Paid members only |
| `draft` | Only admins |

### Checking Access

```ruby
# In controllers (via SiteController)
def check_paid_access!
  unless Current.member&.paid?
    redirect_to pricing_path
  end
end

# In helpers (content truncation)
def should_truncate_content?(post)
  post.paid? && !Current.member&.paid?
end

# In models
post.publicly_accessible?     # Anyone
post.accessible_to?(member)   # Specific member
post.can_access?(member)      # Alias
```

**Graph Note:** `should_truncate_content?()` creates a surprising connection to `authenticated?()`, bridging content helpers with authentication concerns.

## Admin Member Management

File: `app/controllers/admin/members_controller.rb`

### Available Actions

| Action | Description |
|--------|-------------|
| `index` | List all members with filters |
| `show` | Member details + subscription history |
| `create` | Manual member creation |
| `upgrade_to_paid` | Grant complimentary access |
| `cancel_membership` | Cancel subscription |
| `reactivate_membership` | Reactivate cancelled |

### Member Status Badge

```erb
<%# app/views/admin/members/_status_badge.html.erb %>
<span class="badge <%= member_status_class(member) %>">
  <%= member.status_label %>
</span>
```

## Member Pages

File: `site/pages/members/`

Static pages for member flows:

```
site/pages/members/
├── signin.md      # Magic link request form
├── signup.md      # New member registration
├── account.md     # Member dashboard
└── unsubscribe.md # Newsletter unsubscribe
```

## Email Confirmation

Members must confirm their email before accessing content:

```ruby
# Members::AccountsController#confirm_email
def confirm_email
  member = Member.find_by(confirmation_token: params[:token])
  
  if member&.confirm_email!(params[:token])
    redirect_to account_path, notice: "Email confirmed!"
  else
    redirect_to root_path, alert: "Invalid or expired token"
  end
end
```

## Newsletter Subscriptions

Members can unsubscribe from newsletters while keeping their account:

```ruby
# Members::SubscriptionsController
member.unsubscribe_from_newsletter!
```

## Integration Points

### With Stripe (Payments)
- `Member.upgrade_to_paid_with_stripe!` - Called on successful checkout
- `Member.cancel!` - Called when subscription cancelled
- `stripe_customer_id` links to Stripe Customer

### With Postmark (Email)
- `MemberMailer.magic_link` - Sends sign-in email
- `MemberMailer.welcome` - New member welcome
- `MemberMailer.email_confirmation` - Email verification

### With Content System
- `HasAudience` concern uses `member.can_access?`
- `should_truncate_content?` helper checks member status
- Feed controllers check `member.paid?` for private podcast feeds

## Configuration

Enable members in `site/system/features/members.yml`:

```yaml
enabled: true
allow_signups: true
require_email_confirmation: true
```

## Security Considerations

1. **Token Expiration**: Magic links expire after 24 hours (configurable)
2. **Token Regeneration**: New token on each sign-in invalidates old links
3. **Session Storage**: Member ID only, no sensitive data in session
4. **CSRF Protection**: All authentication endpoints protected
5. **Rate Limiting**: Consider adding to magic link endpoints

## Testing

```ruby
# test/models/member_test.rb
test "paid member can access premium content" do
  member = create(:member, :paid)
  post = create(:post, audience: :paid)
  
  assert member.can_access?(post)
end

test "free member cannot access premium content" do
  member = create(:member, :free)
  post = create(:post, audience: :paid)
  
  assert_not member.can_access?(post)
end
```

## Related

- [Payments & Stripe](./12-payments-stripe.md) - Subscription management
- [Email & Newsletters](./14-email-newsletters.md) - Member communications
- [Content System](./02-content-system.md) - Audience field in frontmatter
- [Routes](./08-routes.md) - Member-facing route structure
