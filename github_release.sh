#!/bin/bash
# ============================================================
# github_release.sh — Git commit + push + GitHub release
# ============================================================
# Opens your default editor for the commit message, then
# automatically pushes and creates a GitHub release with the DMG.
#
# Usage:
#   ./github_release.sh             → Uses VERSION file
#   ./github_release.sh 2.1.0       → Explicit version
# ============================================================

set -euo pipefail

cd "$(dirname "$0")"

# --- Resolve version ---
VERSION="${1:-$(cat VERSION | tr -d '[:space:]')}"
DMG_NAME="Nvidia-AI-Studio-${VERSION}.dmg"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  🐙 GitHub Release Pipeline                 ║"
echo "║  📦 Version: v$VERSION                         ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# --- Pre-flight checks ---
if [ ! -f "$DMG_NAME" ]; then
    echo "❌ DMG not found: $DMG_NAME"
    echo "   Run ./build_production.sh first"
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo "❌ GitHub CLI (gh) not installed. Install with: brew install gh"
    exit 1
fi

# Check for changes
CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHANGES" -eq 0 ]; then
    echo "⚠️  No changes to commit. Skipping to push & release."
    SKIP_COMMIT=true
else
    SKIP_COMMIT=false
fi

# --- Step 1: Git commit (interactive editor) ---
if [ "$SKIP_COMMIT" = false ]; then
    echo "📝 [1/3] Opening editor for commit message..."
    echo "   (Save and close the editor to continue)"
    echo ""

    # Stage all changes
    git add -A

    # Show what's being committed
    echo "   Changed files:"
    git diff --cached --stat | sed 's/^/   /'
    echo ""

    # Open the default editor for commit message
    # Uses $EDITOR (or nano/vim fallback), shows a diff in the editor
    git commit --verbose

    echo "✅ Committed!"
fi

# --- Step 2: Git push ---
echo "🚀 [2/3] Pushing to origin..."
BRANCH=$(git branch --show-current)
git push origin "$BRANCH" 2>&1
echo "✅ Pushed to $BRANCH!"

# --- Step 3: GitHub release ---
echo "🏷️  [3/3] Creating GitHub release v$VERSION..."

# Generate release notes from last commit
COMMIT_MSG=$(git log -1 --pretty=%B)

gh release create "v$VERSION" \
    --title "v$VERSION" \
    --notes "$COMMIT_MSG" \
    "$DMG_NAME"

RELEASE_URL=$(gh release view "v$VERSION" --json url -q '.url')

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║  ✅ Release published!                      ║"
echo "║  🔗 $RELEASE_URL"
echo "╚══════════════════════════════════════════════╝"
echo ""
