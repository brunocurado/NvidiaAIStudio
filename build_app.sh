#!/bin/bash
# ============================================================
# build_app.sh — Build Nvidia AI Studio as a native macOS .app
# ============================================================
# ============================================================
# Usage:
#   ./build_app.sh                → Debug build (version from VERSION file)
#   ./build_app.sh release        → Release build (version from VERSION file)
#   ./build_app.sh release 2.0.5  → Release build with explicit version
#
# Output: ./build/Nvidia AI Studio.app
# ============================================================

set -euo pipefail

MODE="${1:-debug}"
VERSION="${2:-}"
APP_NAME="Nvidia AI Studio"
BUNDLE_ID="com.nvidia.aistudio"
PRODUCT_NAME="NvidiaAIStudio"
BUILD_DIR="$(pwd)/NvidiaAIStudio/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Resolve version: CLI arg > VERSION file > fallback
if [ -z "$VERSION" ]; then
    if [ -f "$(pwd)/VERSION" ]; then
        VERSION="$(cat "$(pwd)/VERSION" | tr -d '[:space:]')"
    else
        VERSION="1.0.0"
    fi
fi
echo "📦 Version: ${VERSION}"

echo "🔨 Building ${APP_NAME} (${MODE})..."

# 1. Compile with Swift Package Manager
if [ "$MODE" = "release" ]; then
    swift build -c release 2>&1
    BINARY_PATH=".build/release/${PRODUCT_NAME}"
else
    swift build 2>&1
    BINARY_PATH=".build/debug/${PRODUCT_NAME}"
fi

if [ ! -f "${BINARY_PATH}" ]; then
    echo "❌ Build failed — binary not found at ${BINARY_PATH}"
    exit 1
fi

echo "📦 Packaging ${APP_NAME}.app..."

# 2. Create .app bundle structure
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# 3. Copy binary
cp "${BINARY_PATH}" "${MACOS_DIR}/${PRODUCT_NAME}"

# 4. Copy Resources (.env for API keys, AppIcon.icns for the app icon, PromptMaster)
if [ -f ".env" ]; then
    cp ".env" "${RESOURCES_DIR}/.env"
fi
if [ -f "NvidiaAIStudio/Resources/AppIcon.icns" ]; then
    cp "NvidiaAIStudio/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -d "NvidiaAIStudio/Resources/PromptMaster" ]; then
    cp -R "NvidiaAIStudio/Resources/PromptMaster" "${RESOURCES_DIR}/PromptMaster"
fi

# 5. Create Info.plist
cat > "${CONTENTS_DIR}/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>NvidiaAIStudio</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.nvidia.aistudio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Nvidia AI Studio</string>
    <key>CFBundleDisplayName</key>
    <string>Nvidia AI Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Nvidia AI Studio</string>
</dict>
</plist>
PLIST

# 6. Create a simple app icon (green gradient square with "AI")
# Using a placeholder — replace with a proper .icns later
# For now, we create a minimal PkgInfo
echo "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo ""
echo "✅ ${APP_NAME}.app built successfully!"
echo "📍 Location: ${APP_DIR}"
echo ""
echo "To install:"
echo "  cp -r \"${APP_DIR}\" /Applications/"
echo ""
echo "Or drag '${APP_DIR}' to your Dock."
echo ""

# Open the build folder in Finder
open "${BUILD_DIR}"
