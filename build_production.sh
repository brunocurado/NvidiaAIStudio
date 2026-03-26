#!/bin/bash
# ============================================================
# build_production.sh — Production build + DMG for distribution
# ============================================================
# Usage:
#   ./build_production.sh           → Auto-bump patch version
#   ./build_production.sh 2.1.0     → Explicit version
# ============================================================

set -euo pipefail

cd "$(dirname "$0")"

# --- Resolve version ---
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    # Auto-bump: read current version and increment patch
    CURRENT=$(cat VERSION | tr -d '[:space:]')
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
    PATCH=$((PATCH + 1))
    VERSION="${MAJOR}.${MINOR}.${PATCH}"
fi

echo "$VERSION" > VERSION
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  🚀 Nvidia AI Studio — Production Build     ║"
echo "║  📦 Version: $VERSION                          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# --- Step 1: Production compile ---
echo "🔨 [1/3] Compiling release build..."
swift build -c release 2>&1
BINARY=".build/release/NvidiaAIStudio"

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed — binary not found"
    exit 1
fi
echo "✅ Build complete!"

# --- Step 2: Package .app bundle ---
echo "📦 [2/3] Packaging .app bundle..."
bash build_app.sh release "$VERSION" 2>&1 | tail -3

APP_DIR="NvidiaAIStudio/build/Nvidia AI Studio.app"
if [ ! -d "$APP_DIR" ]; then
    echo "❌ App bundle not found"
    exit 1
fi

# --- Step 3: Create DMG ---
DMG_NAME="Nvidia-AI-Studio-${VERSION}.dmg"
echo "💿 [3/3] Creating DMG: $DMG_NAME"

DMG_DIR="dmg_staging"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_DIR" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "Nvidia AI Studio" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_NAME" 2>&1 | tail -1

rm -rf "$DMG_DIR"

DMG_SIZE=$(du -h "$DMG_NAME" | cut -f1 | tr -d ' ')

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ Build complete!                          ║"
echo "║  📦 $DMG_NAME ($DMG_SIZE)"
echo "║  📍 $(pwd)/$DMG_NAME"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Next: ./github_release.sh"
