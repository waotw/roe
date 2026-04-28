# Troubleshooting

Common issues and solutions for Roe development and production.

## Content Sync Issues

### Posts not appearing after edit

**Symptoms:** Edited file not reflected on site

**Check:**
1. File saved with `.md` extension
2. YAML frontmatter valid (no syntax errors)
3. Post status not `draft`
4. ContentSync ran (check logs)

**Fix:**
```bash
# Force resync
bin/rails content:sync

# Or restart server in development
```

### Sync fails with error

**Symptoms:** `ContentSync.sync_all` raises exception

**Common causes:**
- Invalid YAML in frontmatter
- Malformed Markdown
- Duplicate slugs
- Missing required fields

**Debug:**
```ruby
# Find problematic file
bin/rails runner "
  Dir.glob('site/posts/*.md').each do |path|
    begin
      YAML.safe_load_file(path)
    rescue => e
      puts \"#{path}: #{e.message}\"
    end
  end
"
```

## Static Generation Issues

### Build fails

**Symptoms:** `bin/rails static_site:build` errors

**Check:**
1. All required environment variables set
2. Database connection working
3. Output directory writable
4. Sufficient disk space

**Fix:**
```bash
# Clean and rebuild
rm -rf output/
bin/rails static_site:build
```

### Missing pages in output

**Symptoms:** Some pages not in generated site

**Check:**
- Page status is `published`
- Page not excluded from static generation
- No route constraints blocking

### Images not showing in static site

**Check:**
- Images exist in `site/media/`
- Variants generated
- Paths correct in generated HTML

**Fix:**
```bash
# Regenerate variants
bin/rails images:generate_variants

# Rebuild static site
bin/rails static_site:build
```

## Member Authentication Issues

### Magic link not working

**Symptoms:** Token rejected or expired

**Check:**
1. Token hasn't expired (24hr limit)
2. Token not regenerated (each login creates new token)
3. Email URL complete (not truncated)

**Debug:**
```ruby
# Check member token
member = Member.find_by(email: "user@example.com")
member.token_expires_at
member.token
```

### Can't access paid content

**Symptoms:** Paid member sees "Subscribe" instead of content

**Check:**
1. Member `subscription_status` is `active`
2. `subscribed_at` is set
3. `stripe_subscription_id` exists (if Stripe integrated)
4. Post `audience` is correctly set

**Fix:**
```ruby
# Manual upgrade (admin)
member.upgrade_to_paid!(
  stripe_customer_id: "manual",
  stripe_subscription_id: "manual"
)
```

## Payment Issues

### Stripe webhook failing

**Symptoms:** Payments processed but member not upgraded

**Check:**
1. Webhook endpoint accessible publicly
2. Webhook secret matches Stripe dashboard
3. Webhook signature verifying correctly
4. No errors in Rails logs

**Test:**
```bash
# Send test webhook
curl -X POST https://yoursite.com/webhooks/stripe \
  -H "Content-Type: application/json" \
  -d '{"type": "test"}'
```

### Checkout session not created

**Check:**
- Stripe API keys configured
- Product has valid price
- Member email valid
- Network connectivity to Stripe

## Import Issues

### Substack import fails

**Symptoms:** Phase 1, 2, or 3 errors

**Check:**
1. ZIP file valid Substack export
2. Sufficient disk space for extraction
3. Required files present (posts/, subscribers.csv)
4. No encoding issues in CSV

**Retry:**
```ruby
# Retry specific phase
import = Import.find(id)
ImportPostsJob.perform_later(import.id)
```

### Media not importing

**Check:**
- Original URLs still accessible
- Network timeout not exceeded
- Disk space for downloads
- File permissions on media directory

## Email Issues

### Emails not sending

**Symptoms:** Member doesn't receive magic link

**Check:**
1. Postmark configured (or fallback to ActionMailer)
2. From address verified in Postmark
3. API key valid and not expired
4. Not in development mode (check `letter_opener`)

**Debug:**
```ruby
# Send test email
member = Member.first
MemberMailer.magic_link(member).deliver_now
```

### Newsletter not delivering

**Check:**
- `QueueNewsletterBatchesJob` enqueued
- Background workers running
- `SendNewsletterJob` completing
- Postmark not rate limiting

**Monitor:**
```ruby
# Check job status
NewsletterSend.where(post: post).group(:status).count
```

## Database Issues

### SQLite locked

**Symptoms:** `SQLite3::BusyException`

**Fix:**
```yaml
# config/database.yml
development:
  timeout: 10000  # Increase timeout
```

### Schema out of sync

**Fix:**
```bash
bin/rails db:reset
bin/rails content:sync
```

## Performance Issues

### Slow page loads

**Check:**
1. Image variants generated
2. Using `responsive_image_tag`
3. Database queries optimized
4. Static generation for production

**Profile:**
```ruby
# Enable query logging
ActiveRecord::Base.logger = Logger.new(STDOUT)
```

### Memory issues

**Check:**
- Large images not optimized
- Background jobs consuming memory
- ContentSync loading all posts

**Fix:**
```ruby
# Process in batches
Post.find_each do |post|
  # Process one at a time
end
```

## Common Error Messages

### "undefined method for nil"

Usually means:
- Record not found (check IDs)
- Association not loaded (use `.includes`)
- Missing configuration

### "Template is missing"

Check:
- Template file exists
- Correct naming convention
- Post type has associated template

### "Routing Error"

Check:
- Route defined in `config/routes.rb`
- Controller exists
- Action method implemented

## Development Issues

### ContentWatcher not detecting changes

**Fix:**
```bash
# Restart file watcher
bin/rails content:watch

# Or check if inotify available
ulimit -n  # Increase file watch limit
```

### Assets not updating

```bash
# Clear cache
bin/rails tmp:cache:clear
rm -rf tmp/cache/

# Restart server
```

### JavaScript not working

Check:
- Stimulus controllers loaded
- No console errors
- Importmap correct

## Production Issues

### Site down after deploy

**Checklist:**
1. Database migrations run
2. Content synced
3. Environment variables set
4. File permissions correct
5. Static assets compiled

### SSL certificate errors

With custom domain:
- Certificate valid and not expired
- Domain matches certificate
- Intermediate certificates included

## Getting Help

### Check Logs

```bash
# Development
tail -f log/development.log

# Production
tail -f log/production.log

# Search for errors
grep ERROR log/production.log
```

### Debug with Console

```bash
bin/rails console

# Check record
Post.find_by(slug: "my-post")

# Test service
ContentSync.sync_all

# Check config
SiteConfig.current
```

### Validate Files

```bash
# Check YAML syntax
ruby -ryaml -e "YAML.safe_load_file('site/posts/test.md')"

# Check markdown
bin/rails content:validate
```

## Prevention

### Regular Maintenance

```bash
# Weekly
bin/rails media:cleanup
bin/rails content:validate

# Monthly
bin/rails db:backup
```

### Monitoring

Track:
- Error rates (Sentry, Bugsnag)
- Job queue depth
- Disk space
- Database size

## Related

- [Testing](./19-testing.md) - Testing your fixes
- [Deployment](./20-deployment.md) - Production setup
- [Configuration](./06-configuration.md) - Settings reference
- [Architecture](./01-architecture.md) - System overview
