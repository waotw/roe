# Deployment

Deploying Roe to production environments, including static site generation and hosting considerations.

## Deployment Options

### Option 1: Static Site (Recommended)

Generate HTML and deploy to CDN:

```bash
# Build static site
bin/rails static_site:build

# Deploy output/ directory to CDN
# (AWS S3 + CloudFront, Vercel, Netlify, etc.)
```

**Best for:** High traffic, low dynamic content, CDN caching

### Option 2: Rails Application

Deploy Rails app with database:

```bash
# Traditional Rails deployment
# (Kamal, Heroku, Render, etc.)
```

**Best for:** Heavy admin usage, frequent content changes, member features

### Option 3: Hybrid

Static public site + Rails admin:

```
Public Site (Static)     Admin (Rails)
      │                        │
      └────────┬───────────────┘
               │
         Shared Database
         (SQLite or Postgres)
```

**Best for:** Best of both worlds

## Static Site Deployment

### Build Process

```bash
# 1. Sync content
bin/rails content:sync

# 2. Generate static files
bin/rails static_site:build

# 3. Output structure
output/
├── index.html
├── posts/
│   ├── post-1/
│   │   └── index.html
│   └── post-2/
│       └── index.html
├── feed.xml
├── sitemap.xml
└── media/
    └── images/
```

### Hosting Providers

#### Vercel

```bash
# Install CLI
npm i -g vercel

# Deploy
vercel --prod output/
```

#### Netlify

```bash
# Install CLI
npm i -g netlify-cli

# Deploy
netlify deploy --prod --dir=output
```

#### AWS S3 + CloudFront

```bash
# Sync to S3
aws s3 sync output/ s3://your-bucket --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id YOUR_ID \
  --paths "/*"
```

#### GitHub Pages

```bash
# Push output/ to gh-pages branch
git subtree push --prefix output origin gh-pages
```

### CDN Configuration

#### Cache Headers

```
# HTML files - short cache
Cache-Control: public, max-age=60

# Assets (images, CSS) - long cache
Cache-Control: public, max-age=31536000, immutable
```

#### Redirects

```
# _redirects (Netlify)
/rss              /feed.xml      301
/feed            /feed.xml      301

# vercel.json
{
  "redirects": [
    { "source": "/rss", "destination": "/feed.xml", "permanent": true }
  ]
}
```

## Rails Application Deployment

### Kamal (Recommended)

```yaml
# .kamal/deploy.yml
service: roe
image: your-user/roe
servers:
  - 123.456.789.0
registry:
  username: your-user
  password:
    - KAMAL_REGISTRY_PASSWORD
env:
  secret:
    - RAILS_MASTER_KEY
```

Deploy:

```bash
kamal setup
kamal deploy
```

### Heroku

```bash
# Create app
heroku create your-roe-app

# Add PostgreSQL
heroku addons:create heroku-postgresql:mini

# Set environment variables
heroku config:set RAILS_MASTER_KEY=$(cat config/master.key)
heroku config:set RAILS_ENV=production

# Deploy
git push heroku main

# Run migrations
heroku run bin/rails db:migrate
```

### Render

```yaml
# render.yaml
services:
  - type: web
    name: roe
    runtime: ruby
    buildCommand: bundle install
    startCommand: bundle exec puma -C config/puma.rb
    envVars:
      - key: RAILS_MASTER_KEY
        sync: false
      - key: DATABASE_URL
        fromDatabase:
          name: roe-db
          property: connectionString

databases:
  - name: roe-db
    databaseName: roe_production
    user: roe
```

## Environment Variables

### Required

```bash
RAILS_MASTER_KEY           # Encryption key
SECRET_KEY_BASE            # Session encryption
RAILS_ENV=production       # Environment
```

### Database

```bash
# SQLite (default)
DATABASE_URL=sqlite3:storage/production.sqlite3

# PostgreSQL
DATABASE_URL=postgresql://user:pass@localhost/roe_production
```

### External Services

```bash
# Stripe (optional)
STRIPE_PUBLISHABLE_KEY=pk_live_...
STRIPE_SECRET_KEY=sk_live_...

# Postmark (optional)
POSTMARK_API_KEY=...
POSTMARK_FROM_EMAIL=newsletter@yoursite.com

# Snipcart (optional)
SNIPCART_API_KEY=...
```

### Static Generation

```bash
SITE_URL=https://yoursite.com
STATIC_OUTPUT_PATH=output/
```

## Production Checklist

### Pre-Deployment

- [ ] Environment variables configured
- [ ] Database migrations run
- [ ] Content synced
- [ ] Static assets precompiled (if Rails mode)
- [ ] Image variants generated
- [ ] Error tracking enabled (Sentry, Bugsnag)
- [ ] SSL certificate configured

### Post-Deployment

- [ ] Health check passes
- [ ] Content displaying correctly
- [ ] Images loading
- [ ] Feeds accessible
- [ ] Admin login works
- [ ] Email sending (if configured)
- [ ] Payments processing (if configured)
- [ ] Backups configured

## Database Setup

### SQLite (Default)

```bash
# Create production database
RAILS_ENV=production bin/rails db:create

# Run migrations
RAILS_ENV=production bin/rails db:migrate

# Sync content
RAILS_ENV=production bin/rails content:sync
```

### PostgreSQL

```bash
# Create database
createdb roe_production

# Configure database.yml
production:
  adapter: postgresql
  database: roe_production
  username: roe
  password: <%= ENV['DB_PASSWORD'] %>
  host: localhost

# Migrate
RAILS_ENV=production bin/rails db:migrate
```

## Automated Deployment

### GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: .ruby-version
          bundler-cache: true
      
      - name: Build Static Site
        run: |
          bin/rails db:create db:migrate
          bin/rails content:sync
          bin/rails static_site:build
      
      - name: Deploy to Vercel
        uses: vercel/action-deploy@v1
        with:
          vercel-token: ${{ secrets.VERCEL_TOKEN }}
          vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
          vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
          working-directory: ./output
```

## Backup Strategy

### Content Backup

```bash
# Backup site/ directory
tar -czf backup-$(date +%Y%m%d).tar.gz site/

# Or rsync to remote
rsync -avz site/ backup-server:/backups/roe/
```

### Database Backup

```bash
# SQLite
cp storage/production.sqlite3 backups/

# PostgreSQL
pg_dump roe_production > backup-$(date +%Y%m%d).sql
```

### Automated Backups

```ruby
# config/schedule.rb (using whenever gem)
every 1.day, at: '2:00 am' do
  rake 'backup:content'
  rake 'backup:database'
end
```

## SSL/HTTPS

### Let's Encrypt

```bash
# Using certbot
sudo certbot --nginx -d yoursite.com -d www.yoursite.com

# Auto-renewal
crontab -e
# Add: 0 0 * * * certbot renew --quiet
```

### Cloudflare

1. Point DNS to Cloudflare
2. Enable "Always Use HTTPS"
3. Set SSL/TLS mode to "Full (strict)"

## Monitoring

### Health Check Endpoint

```ruby
# config/routes.rb
get '/health', to: proc { [200, {}, ['OK']] }
```

### Uptime Monitoring

- UptimeRobot (free tier)
- Pingdom
- StatusCake

### Error Tracking

```ruby
# Gemfile
gem 'sentry-ruby'
gem 'sentry-rails'

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.environment = Rails.env
end
```

## Performance Optimization

### Image Optimization

```bash
# Pre-generate all variants before deployment
bin/rails images:generate_variants

# Verify in output
ls -la output/media/images/variants/
```

### Compression

```bash
# Enable gzip for HTML/CSS/JS
# (CDN usually handles this)

# Or manually
gzip -kr output/
```

### Caching Headers

Configure your CDN/web server:

```nginx
# nginx.conf
location ~* \.(jpg|jpeg|png|webp|css|js)$ {
  expires 1y;
  add_header Cache-Control "public, immutable";
}

location ~* \.html$ {
  expires 1h;
  add_header Cache-Control "public, must-revalidate";
}
```

## Troubleshooting Deployment

### Build Fails

```bash
# Check disk space
df -h

# Check memory
free -h

# Check logs
tail -f log/production.log
```

### Assets Not Loading

**Check:**
- Asset paths correct
- Files in output directory
- CDN origin configured
- Cache invalidation run

### Database Locked (SQLite)

```yaml
# config/database.yml
production:
  timeout: 10000
  pool: 5
```

### Static Files 404

**Check:**
- Static site built successfully
- Web server root points to output/
- Directory listing not enabled (security)

## Scaling

### Static Sites

- Use CDN for global distribution
- No scaling needed (just files)
- Cost scales with bandwidth, not traffic

### Rails Apps

**Horizontal:**
- Multiple app servers
- Load balancer
- Shared database (Postgres)

**Vertical:**
- Larger instance sizes
- More memory for content sync

### Database

SQLite limitations:
- Single writer
- Not suitable for high concurrency

Upgrade to PostgreSQL for:
- Multiple app servers
- High write volume
- Advanced features (JSON, full-text search)

## Related

- [Configuration](./06-configuration.md) - Environment-specific settings
- [Troubleshooting](./18-troubleshooting.md) - When things go wrong
- [Testing](./19-testing.md) - Testing before deployment
- [Architecture](./01-architecture.md) - System design
