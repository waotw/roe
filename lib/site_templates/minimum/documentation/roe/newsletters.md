---
roe_version: 0.0.20
title: Newsletters
status: published
---

# Newsletters in Roe

Roe has a full featured newsletter system that supports free and paid members. Members can sign up with just their name/email, no password required. 

## Enabling Newsletters in Roe

Before using newsletters, you need to: **Enable Members**: Go to `Admin` → `Settings` and click `ENABLE MEMBERS`.

## Setting Up Postmark

Roe has intregrated with Postmark to send member and newsletter emails. Follow the instructions below to set things up.

### 1. Basic Postmark Setup

Postmark has good documentation. Use this article to get your account set up correctly:  
[Getting started with Postmark](https://postmarkapp.com/support/article/1002-getting-started-with-postmark). This ensures that your emails are delivered reliably. 

**Next:**

1. Sign up for a Postmark account at postmarkapp.com
2. Apply for approval: [How does the account approval process work?](https://postmarkapp.com/support/article/1084-how-does-the-account-approval-process-work)
3. Create a new Server or use the defaults created with your account (you can rename them)
    - [Servers FAQ](https://postmarkapp.com/support/article/1137-servers-faq)
    - [Message Streams Video](https://postmarkapp.com/videos/message-streams) (if curious)
4. Go to your Server → API Tokens tab
5. Copy your Server API Token
6. Paste it above and click Save Configuration

### 2. Connect Postmark to Roe

1. Go to **Admin → Postmark** (upper right)
2. Paste your Server API Token
3. Click **"Save Configuration"**
4. You'll see a green confirmation if successful

### 3. Configure Webhooks

Webhooks tell Roe when emails are delivered, bounce, or are marked as spam:

1. In Postmark, go to Postmark Server → Choose your Broadcast Stream → Settings → Webhooks
2. Click **"Add webhook"**
3. Copy the webhook URL shown in Roe's Postmark settings
4. Paste it into Postmark
5. Enable these events:
   - **Bounce** (required)
   - **Spam Complaint** (required)
   - **Delivery** (optional, for logging)
6. Save the webhook
7. Repeat steps 1-6 for Transactional Stream

## Sending Newsletters

You can send yourself a test email using the `SEND TEST` button. This allows you to preview exactly what will be sent.

### Sending on Publish

`audience` and `published_to` are required in order to publish a Post. If you haven't set them, you can do so when you click `PUBLISH`.

1. Click **"Publish"** on any post
2. Choose your **Published To** option:
   - **Site** - Only appears on website (no email)
   - **Newsletter** - Only sent as email (not on site)
   - **Both** - Appears on site AND sent as email (most common)

3. Choose your **Audience**:
   - **Everyone** - Sent to all newsletter subscribers
   - **Paid** - Only sent to paid members

4. Click **"Publish"**

The newsletter is queued and sent in the background. Under `url_name` you'll see how many members this Newsletter was sent to and when.

### Resending to New Members

1. If new members have joined, you'll see: **"Resend to X new members"**
2. Click the button
3. Confirm the send

**How it works:**

- Only sends to members who joined after the original send
- Respects the post's audience setting (everyone vs paid)
- Prevents duplicate sends automatically
- Queues in background just like original send

## Bounce & Spam Tracking

Roe automatically tracks email deliverability through Postmark webhooks:

### Hard Bounces

When an email address is invalid or mailbox doesn't exist:

- Member's `newsletter_status` is set to **bounced**
- They stop receiving future newsletters
- You can see bounced members in Admin → Members
- Filter by `Newsletter Status` to see who's bounced

### Soft Bounces

Temporary delivery failures (mailbox full, server down):

- Tracked in member metadata as `soft_bounce_count`
- After **5 soft bounces**, automatically treated as hard bounce
- Prevents wasting sends on problematic addresses

### Spam Complaints

When someone marks your email as spam:

- Member is **immediately unsubscribed** (legal requirement)
- `newsletter_status` set to **unsubscribed**
- They won't receive future emails
- You can see this in Admin → Members

### Deliveries

Successful deliveries are logged but don't change member status.

## Managing Newsletter Subscribers

Go to **Admin → Members** to manage your list:

### View Newsletter Status

The member list shows a **Newsletter** column with status icons:

- 📬 **Subscribed** - Will receive newsletters
- 🔕 **Unsubscribed** - Opted out or spam complaint
- ⚠️ **Bounced** - Email address is invalid

### Filter by Newsletter Status

Use the dropdown to filter:
- All Newsletter Status
- 📬 Subscribed
- 🔕 Unsubscribed  
- ⚠️ Bounced

This helps you:
- See your active newsletter list
- Clean up bounced addresses
- Check who's unsubscribed

### Member Detail View

Click any member to see their newsletter status and when they subscribed.

## Unsubscribe Flow

Members can unsubscribe in two ways:

### 1. Unsubscribe Link in Email

Every newsletter includes an unsubscribe link in the footer:

1. Member clicks "Unsubscribe"
2. Taken to confirmation page
3. Clicks "Unsubscribe from newsletter"
4. Status changed to unsubscribed
5. Confirmation message shown

### 2. Account Settings

Signed-in members can manage their subscription in their account page.

## Email Templates

Newsletter emails are rendered using your active theme's styles, ensuring brand consistency. The system automatically:

- Converts markdown to HTML
- Inlines CSS for email compatibility
- Makes all URLs absolute (not relative)
- Adds responsive styles for mobile
- Includes proper email headers

You can customize the email template by editing your theme's CSS.

## Technical Details

### Send Tracking

Every send is recorded in the database:

- Post ID + Member ID = unique send record
- Tracks when it was sent
- Stores Postmark message ID
- Used to prevent duplicates and enable resends

## Best Practices

The newsletter system is designed to be reliable and hands-off - set it up once, and it handles sending, tracking, and list management automatically. When you send a newsletter to your full audience, check: Admin → Members and check the Bounced Newletter Status to see if you're getting more bounces than expected.

Always a good idea to check Postmark from time to time. You can check on specific email deliveries, make sure your domain is setup correctly, etc.
