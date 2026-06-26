#!/bin/bash
set -e

echo "🚀 Roe Deployment"
echo "===================="

# Detect directory structure
# In versioned setup: we're in /roe/current/, site is in /roe/site/
if [ "$(basename "$(pwd)")" = "current" ]; then
    echo "📁 Detected versioned structure (current/)"
else
    echo "📁 Detected standard structure"
fi

# Check requirements
if ! command -v fly &> /dev/null; then
    echo "❌ Fly CLI not found. Install: https://fly.io/docs/hands-on/install-flyctl/"
    exit 1
fi

if ! fly auth whoami &> /dev/null; then
    echo "❌ Not authenticated with Fly.io. Run: fly auth login"
    exit 1
fi

# 1. Backup production
echo ""
echo "💾 Step 1: Backing up production..."
rake site:backup

# 2. Preview what will be pushed to production
echo ""
read -p "Preview what would sync to production? (y/n) " -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rake site:preview_changes
fi

# 3. Choose push strategy
echo ""
echo "Content sync options:"
echo "  1) Push everything (overwrite all production content)"
echo "  2) Push specific folders (e.g., posts, theme, media)"
echo "  3) Skip content push (code-only deploy)"
echo ""
read -p "Choose (1/2/3): " push_option

# Add validation for empty input
if [[ -z "$push_option" ]]; then
    echo "❌ No option selected"
    exit 1
fi

case $push_option in
  1)
    echo ""
    rake site:push
    ;;
  2)
    echo ""
    echo "Available folders: posts, pages, pages/members, media, theme, system (or any path under site/)"
    read -p "Enter folders to push (comma-separated): " folders
    rake site:push_folders[$folders]
    ;;
  3)
    echo "⏭️  Skipping content push"
    ;;
  *)
    echo "❌ Invalid option: '$push_option'"
    exit 1
    ;;
esac

# 4. Confirm deploy
echo ""
read -p "🚢 Deploy application code to Fly.io? (y/n) " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deploy cancelled"
    exit 1
fi

# 5. Prepare build context
echo ""
echo "📋 Preparing build context..."
# Copy VERSION from root to current/ so Docker can access it
if [ -f "../VERSION" ]; then
    cp ../VERSION ./VERSION
    echo "✅ VERSION file copied"
fi

# 6. Deploy
echo ""
echo "🚢 Deploying to Fly.io..."
fly deploy --local-only

# 7. Cleanup
echo ""
echo "🧹 Cleaning up..."
rm -f ./VERSION

# 6. Health check
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
# Show backup location based on directory structure
if [ "$(basename "$(pwd)")" = "current" ]; then
    echo "📂 Backup: ../site_backups/$(ls -t ../site_backups 2>/dev/null | head -1)"
else
    echo "📂 Backup: site_backups/$(ls -t site_backups 2>/dev/null | head -1)"
fi
