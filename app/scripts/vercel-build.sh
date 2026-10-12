#!/usr/bin/env bash
# Builds the Flutter web app on Vercel. Vercel build images do not ship Flutter,
# so the stable SDK is cloned into the build cache on first run.
#
# Required environment variables (Project Settings > Environment Variables):
#   SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL, WEB_APP_URL
set -euo pipefail

FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"
FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Cloning Flutter ($FLUTTER_CHANNEL)..."
  git clone --depth 1 -b "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true
flutter pub get

cat > env.json <<EOF
{
  "SUPABASE_URL": "${SUPABASE_URL:?SUPABASE_URL is required}",
  "SUPABASE_ANON_KEY": "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY is required}",
  "API_BASE_URL": "${API_BASE_URL:?API_BASE_URL is required}",
  "WEB_APP_URL": "${WEB_APP_URL:-}"
}
EOF

flutter build web --release --dart-define-from-file=env.json
