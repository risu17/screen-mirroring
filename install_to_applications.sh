#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=================================================="
echo "   Building & Installing Phone Mirroring App      "
echo "=================================================="

# Stop running instances
pkill -f "PhoneMirroring" 2>/dev/null || true
pkill -f "DroidMirror" 2>/dev/null || true

# 1. Rebuild and codesign universal app
"$DIR/macos/build_app.sh"

TARGET_DIR="$HOME/Applications"
mkdir -p "$TARGET_DIR"

echo "==> Cleaning old installations..."
rm -rf "$TARGET_DIR/DroidMirror.app"
rm -rf "$TARGET_DIR/Phone Mirroring.app"

echo "==> Installing 'Phone Mirroring.app' into $TARGET_DIR..."
cp -R "$DIR/Phone Mirroring.app" "$TARGET_DIR/"

# Remove quarantine from installed copy
xattr -cr "$TARGET_DIR/Phone Mirroring.app" 2>/dev/null || true

echo "==> Codesigning installed copy at $TARGET_DIR/Phone Mirroring.app..."
codesign --force --deep --sign - --entitlements "$DIR/macos/Resources/Screen Sharing.entitlements" "$TARGET_DIR/Phone Mirroring.app"

# Refresh icon cache and Finder metadata
touch "$TARGET_DIR/Phone Mirroring.app"
killall Dock 2>/dev/null || true

echo "==> Launching $TARGET_DIR/Phone Mirroring.app..."
open "$TARGET_DIR/Phone Mirroring.app"

echo "==> Phone Mirroring successfully installed and launched!"
