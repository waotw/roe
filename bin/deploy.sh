#!/bin/bash
set -e

echo "🚀 Roe CMS Deployment"
echo "===================="

# Check requirements
if ! command -v fly &> /dev/null; then
    echo "❌ Fly CLI not found. Install: https://fly.io/docs/hands-on/install-flyctl/"
    exit 1
fi

if ! fly auth whoami &> /dev/null; then
    echo "❌ Not authenticated with Fly.io. Run: fly auth login"
    exit 1
fi

# 1. Backup production first
echo ""
echo "💾 Step 1: Backing up production..."
rake content:backup_site

# 2. Pull latest changes
echo ""
echo "📥 Step 2: Pulling production changes..."
rake content:pull_site

# 3. Preview changes (optional)
echo ""
read -p "Preview what would sync? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rake content:preview_changes
fi

# 4. Choose push strategy
echo ""
echo "Content sync options:"
echo "  1) Push everything (overwrite all production content)"
echo "  2) Push specific folders (e.g., posts, theme, media)"
echo "  3) Skip content push (code-only deploy)"
echo ""
read -p "Choose (1/2/3): " push_option

case $push_option in
  1)
    echo ""
    rake content:push_site
    ;;
  2)
    echo ""
    echo "Available folders: posts, pages, media, theme, system"
    read -p "Enter folders to push (comma-separated): " folders
    rake content:push_folders[$folders]
    ;;
  3)
    echo "⏭️  Skipping content push"
    ;;
  *)
    echo "❌ Invalid option"
    exit 1
    ;;
esac

# 5. Confirm deploy
echo ""
read -p "🚢 Deploy application code to Fly.io? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deploy cancelled"
    exit 1
fi

# 6. Deploy
echo ""
echo "🚢 Deploying to Fly.io..."
fly deploy --local-only

# 7. Health check
echo ""
echo "🏥 Health check..."
APP_URL=$(fly status --json | jq -r '.Hostname')
if curl -f "https://${APP_URL}/health" &> /dev/null; then
    echo "✅ Health check passed"
else
    echo "⚠️  Health check failed - check logs: fly logs"
fi

echo ""
echo "✅ Deployment complete!"
echo "🌐 Visit: https://${APP_URL}"
echo "📂 Backup: site_backups/$(ls -t site_backups | head -1)"
