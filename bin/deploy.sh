#!/bin/bash
set -e

echo "🚀 Roe CMS Deployment"
echo "===================="

# Check if fly CLI is installed
if ! command -v fly &> /dev/null; then
    echo "❌ Fly CLI not found. Install: https://fly.io/docs/hands-on/install-flyctl/"
    exit 1
fi

# Check if authenticated
if ! fly auth whoami &> /dev/null; then
    echo "❌ Not authenticated with Fly.io. Run: fly auth login"
    exit 1
fi

# 1. Pull remote media
echo ""
echo "📥 Step 1: Pulling production media..."
rake content:sync_site

# 2. Confirm deploy
echo ""
read -p "✅ Ready to deploy? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Deploy cancelled"
    exit 1
fi

# 3. Deploy
echo ""
echo "🚢 Step 3: Deploying to Fly.io..."
fly deploy --local-only

# 6. Health check
echo ""
echo "🏥 Step 5: Running health check..."
APP_URL=$(fly status --json | jq -r '.Hostname')
if curl -f "https://${APP_URL}/health" | jq .; then
    echo "✅ Health check passed"
else
    echo "⚠️  Health check failed - check logs: fly logs"
fi

echo ""
echo "✅ Deployment complete!"
echo "🌐 Visit: https://${APP_URL}"
