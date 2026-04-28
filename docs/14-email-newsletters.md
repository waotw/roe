# Email & Newsletters

Roe uses Postmark for transactional and broadcast emails with fallback to ActionMailer. The architecture separates email delivery tracking from content generation.

## Architecture Overview

```
Newsletter Post
      │
      ▼
┌─────────────────────────────────────┐
│   Admin::PostsController            │
│   #send_newsletter                  │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   QueueNewsletterBatchesJob         │
│   • Split into batches (100)        │
│   • Queue SendNewsletterJob         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   SendNewsletterJob                 │
│   • Render email per-member         │
│   • Send via PostmarkService        │
│   • Track in NewsletterSend         │
└────────────────────┬────────────────┘
                     │
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐      ┌─────────────────┐
│  Postmark API   │      │  Fallback       │
│  (Primary)      │      │  (ActionMailer) │
└─────────────────┘      └─────────────────┘
```

**Graph Note:** Email integration spans the Payment & Email Integration community (21 nodes), connecting Postmark configuration, member management, and newsletter delivery tracking.

## Configuration

File: `app/models/postmark_config.rb`

### Configuration File

```yaml
# site/system/features/email.yml
enabled: true
server_token: "..."  # Encrypted
webhook_token: "..." # For inbound webhooks
from_email: "newsletter@example.com"
from_name: "Your Name"
reply_to: "reply@example.com"
```

### Connection Check

```ruby
# PostmarkConfig#connected?
def connected?
  PostmarkService.health_check
rescue
  false
end
```

## Email Templates

Location: `site/emails/`

### Template Files

```
site/emails/
├── welcome.md              # New member welcome
├── magic_link.md           # Sign-in link
├── email_confirmation.md   # Email verification
├── upgrade_success.md      # Subscription upgrade
├── payment_failed.md       # Failed payment notice
├── membership_cancelled.md # Cancellation confirmation
└── newsletter.md           # Default newsletter template
```

### Template Format

```markdown
---
subject: "Welcome to {{site.title}}"
---

Hi {{member.name}},

Welcome to {{site.title}}! We're excited to have you.

{{content}}

Thanks,  
{{site.author}}
```

### Available Variables

| Variable | Description |
|----------|-------------|
| `{{site.title}}` | Site name from site.yml |
| `{{site.author}}` | Site author |
| `{{site.url}}` | Site URL |
| `{{member.email}}` | Member email |
| `{{member.name}}` | Member name (if provided) |
| `{{member.token}}` | Magic link token |
| `{{member.unsubscribe_token}}` | Newsletter unsubscribe token |
| `{{content}}` | Post content (newsletters only) |

## MemberMailer

File: `app/mailers/member_mailer.rb`

**Note:** Unlike standard Rails mailers, `MemberMailer` uses class methods that route through `PostmarkService`:

```ruby
class MemberMailer
  def self.magic_link(member)
    deliver(
      to: member.email,
      template: 'magic_link',
      variables: { member: member }
    )
  end
  
  def self.welcome(member)
    deliver(
      to: member.email,
      template: 'welcome',
      variables: { member: member }
    )
  end
  
  private
  
  def self.deliver(to:, template:, variables:)
    if PostmarkConfig.current&.connected?
      PostmarkService.send(to: to, template: template, variables: variables)
    else
      FallbackMailer.send(to: to, template: template, variables: variables)
    end
  end
end
```

## Newsletter Broadcasts

### Sending a Newsletter

1. Create a post with `post_type: article` (or any type)
2. In Admin → Posts, click "Send as Newsletter"
3. Review recipient count
4. Click "Send"

### Batch Processing

Large newsletters are split into batches:

```ruby
# QueueNewsletterBatchesJob
def perform(post_id)
  post = Post.find(post_id)
  members = Member.newsletter_subscribers
  
  members.find_in_batches(batch_size: 100) do |batch|
    SendNewsletterJob.perform_later(post, batch.pluck(:id))
  end
end
```

### Individual Delivery

```ruby
# SendNewsletterJob
def perform(post, member_ids)
  members = Member.where(id: member_ids)
  
  members.each do |member|
    content = NewsletterRenderer.render(post, member)
    
    MemberMailer.newsletter(
      member: member,
      subject: post.title,
      content: content
    )
    
    NewsletterSend.create!(
      post: post,
      member: member,
      sent_at: Time.current
    )
  end
end
```

## NewsletterSend Tracking

File: `app/models/newsletter_send.rb`

Tracks delivery status for each recipient:

```ruby
class NewsletterSend
  belongs_to :post
  belongs_to :member
  
  # Status: pending, sent, delivered, bounced, complained, unsubscribed
end
```

### Querying Delivery Status

```ruby
# How many received?
post.newsletter_sends.where(status: 'delivered').count

# Who bounced?
post.newsletter_sends.where(status: 'bounced').includes(:member)

# Delivery rate
(post.newsletter_sends.delivered.count.to_f / post.newsletter_sends.count * 100).round(1)
```

## Postmark Webhooks

File: `app/controllers/webhooks/postmark_controller.rb`

Handle delivery events from Postmark:

### Delivery Event

```ruby
def create
  case params['RecordType']
  when 'Delivery'
    handle_delivery
  when 'Bounce'
    handle_bounce
  when 'SpamComplaint'
    handle_spam_complaint
  when 'SubscriptionChange'
    handle_unsubscribe
  end
  
  head :ok
end
```

### Event Handlers

```ruby
def handle_delivery
  send = NewsletterSend.find_by(message_id: params['MessageID'])
  send&.update!(status: 'delivered', delivered_at: Time.current)
end

def handle_bounce
  send = NewsletterSend.find_by(message_id: params['MessageID'])
  send&.update!(status: 'bounced')
  
  # Optionally: Pause sending to this member
  send.member.update!(email_issues: true)
end

def handle_unsubscribe
  member = Member.find_by(email: params['Recipient'])
  member&.unsubscribe_from_newsletter!
end
```

## Newsletter Rendering

File: `app/services/newsletter_renderer.rb`

Converts posts to email-friendly HTML:

```ruby
class NewsletterRenderer
  def self.render(post, member)
    content = post.to_html
    
    # Add unsubscribe footer
    footer = generate_footer(member)
    
    # Inline CSS for email clients
    inlined = Premailer.new(
      content + footer,
      with_html_string: true
    ).to_inline_css
    
    inlined
  end
  
  private
  
  def self.generate_footer(member)
    <<~HTML
      <hr>
      <p style="font-size: 12px; color: #666;">
        You're receiving this because you subscribed to #{Current.site.title}.
        <a href="#{unsubscribe_url(member)}">Unsubscribe</a>
      </p>
    HTML
  end
end
```

## Fallback Mailer

When Postmark is not configured, emails fall back to ActionMailer:

```ruby
# app/mailers/fallback_mailer.rb
class FallbackMailer < ApplicationMailer
  def newsletter(member:, subject:, content:)
    @content = content
    mail(
      to: member.email,
      subject: subject
    )
  end
end
```

Development uses `letter_opener` to preview emails in browser.

## Admin Interface

### Email Configuration

**Admin → Config → Email:**

- Postmark server token (encrypted)
- Webhook token for inbound processing
- From name and email
- Reply-to address
- Connection status indicator
- Test email button

### Newsletter Status

**Admin → Posts → Newsletter Status:**

- Recipients count
- Sent count
- Delivered count
- Bounced count
- Delivery rate percentage
- Individual recipient status

### Email Templates Editor

**Admin → Settings → Email Templates:**

- Edit each template file
- Preview with variable substitution
- Test send to admin email
- Variable reference guide

## Best Practices

### Subject Lines

- Keep under 50 characters
- Use personalization: "{{member.name}}, new post"
- Avoid spam trigger words
- A/B test when possible

### Content

- Use plain text + simple HTML
- Inline all CSS (no external stylesheets)
- Include clear unsubscribe link
- Test in multiple email clients
- Mobile-friendly (60+ chars width)

### Deliverability

- Verify domain with Postmark (SPF, DKIM, DMARC)
- Warm up new sending domains gradually
- Monitor bounce rates (<5%)
- Remove bounced emails promptly
- Honor unsubscribe requests immediately

## Configuration

Enable newsletters in `site/system/features/members.yml`:

```yaml
enabled: true
newsletters_enabled: true
require_confirmation: true
```

## Testing

### Send Test Email

```ruby
# Rails console
member = Member.first
MemberMailer.welcome(member)
```

### Preview in Development

```ruby
# http://localhost:3000/rails/mailers
Rails.application.routes.url_helpers.rails_mailers_path
```

### Webhook Testing

Use Postmark CLI to simulate webhooks:

```bash
curl -X POST http://localhost:3000/webhooks/postmark \
  -H "Content-Type: application/json" \
  -d '{
    "RecordType": "Delivery",
    "MessageID": "test-123",
    "Recipient": "test@example.com"
  }'
```

## Troubleshooting

### Emails not sending

**Check:**
- Postmark token configured and valid
- `from_email` domain verified in Postmark
- Postmark account not in test mode
- `FallbackMailer` if Postmark unavailable

### High bounce rate

**Check:**
- Member emails are confirmed
- Old/unused emails cleaned up
- No role-based emails (admin@, info@)

### Webhooks not working

**Check:**
- Webhook URL publicly accessible
- `webhook_token` matches Postmark
- Rails logs for processing errors

### Emails in spam

**Check:**
- SPF/DKIM/DMARC records configured
- Sending domain reputation
- Content not spammy
- Unsubscribe link present

## Related

- [Members & Authentication](./11-members-authentication.md) - Member model and subscriptions
- [Configuration](./06-configuration.md) - Feature flags and site settings
- [Content System](./02-content-system.md) - Post types and content
- [Admin UI](./07-admin-ui.md) - Email template editor
