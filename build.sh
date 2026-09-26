#!/bin/bash
set -euo pipefail

APP_NAME="Prune"
BUNDLE_NAME="Prune"
APP_BUNDLE="${APP_NAME}.app"
RESOURCE_BUNDLE="Prune_PruneDefinitions.bundle"

echo "Building release binary..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "Assembling app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BIN_DIR/$BUNDLE_NAME" "$APP_BUNDLE/Contents/MacOS/$BUNDLE_NAME"

# Copy Info.plist
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Copy the SwiftPM resource bundle that carries artifacts.json. The app looks
# for it in Contents/Resources (see Definitions/PruneDefinitions.swift).
if [ ! -d "$BIN_DIR/$RESOURCE_BUNDLE" ]; then
    echo "error: $BIN_DIR/$RESOURCE_BUNDLE was not produced by swift build" >&2
    exit 1
fi
cp -R "$BIN_DIR/$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
if [ ! -f "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE/artifacts.json" ]; then
    echo "error: artifacts.json is missing from $APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE" >&2
    exit 1
fi

# Copy icon if it exists
if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc code sign
echo "Signing..."
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "To create DMG, run: ./dmg.sh"
