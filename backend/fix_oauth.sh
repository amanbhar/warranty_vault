#!/bin/bash

# OAuth Fix Script
# This script sets up the correct environment variables and restarts the server

echo "🔧 Fixing OAuth Configuration..."
echo "================================"

# Kill any existing Rails server on port 3005
echo "🛑 Stopping any existing server on port 3005..."
pkill -f "rails.*3005" 2>/dev/null || true
sleep 2

# Set environment variables
echo "📝 Setting environment variables..."
export APP_URL="http://localhost:3005"
export FRONTEND_URL="http://localhost:3006"
export GOOGLE_REDIRECT_URI="http://localhost:3005/auth/google/callback"
export REDIS_URL="redis://localhost:6379/0"

echo "✅ Environment variables set:"
echo "   APP_URL: $APP_URL"
echo "   FRONTEND_URL: $FRONTEND_URL"
echo "   GOOGLE_REDIRECT_URI: $GOOGLE_REDIRECT_URI"
echo "   REDIS_URL: $REDIS_URL"

# Start the server
echo ""
echo "🚀 Starting Rails server with OAuth fix..."
echo "   Server will be available at: http://localhost:3005"
echo "   OAuth callback: http://localhost:3005/auth/google/callback"
echo ""
echo "📋 Test the OAuth flow:"
echo "   1. Visit your frontend at http://localhost:3006"
echo "   2. Click 'Login with Google'"
echo "   3. Should redirect to Google, then back to backend, then to frontend"
echo ""

# Start Rails server in foreground
cd /home/dev37/work/vault_ai/warranty_vault_api
bundle exec rails server -p 3005 -b 0.0.0.0
