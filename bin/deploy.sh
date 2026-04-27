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

# 1. Sync local theme changes to app/themes (for version control)
echo ""
echo "🎨 Step 1: Syncing local theme to app/themes..."
echo "===================="

if [ -d "site/theme" ]; then
    rsync -av --delete site/theme/ app/themes/
    echo "✅ Theme synced from site/theme → app/themes"

  # Check if there are uncommitted theme changes
  if ! git diff --quiet app/themes/; then
      echo ""
      echo "⚠️  Theme changes detected in app/themes/"
      echo ""
      read -p "Review and commit theme changes now? (y/n) " -r
      if [[ $REPLY =~ ^[Yy]$ ]]; then
          echo ""
          git add app/themes/
          echo "Theme changes staged for commit."
          echo ""
          read -p "Commit message: " commit_msg
          git commit -m "${commit_msg:-Update theme CSS}"
          echo "✅ Theme changes committed"
      fi
  fi
else
    echo "⚠️  No site/theme folder found"
fi

# 2. Backup production
echo ""
echo "💾 Step 2: Backing up production..."
rake site:backup

# 3. Preview what will be pushed to production
echo ""
read -p "Preview what would sync to production? (y/n) " -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rake site:preview_changes
fi

# 4. Choose push strategy
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

# 5. Confirm deploy
echo ""
read -p "🚢 Deploy application code to Fly.io? (y/n) " -r
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
