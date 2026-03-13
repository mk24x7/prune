#!/bin/bash
set -e

APP_NAME="Prune"

if [ ! -d "$APP_NAME.app" ]; then
    echo "Error: '$APP_NAME.app' not found. Run ./build.sh first."
    exit 1
fi

echo "Creating DMG..."

# Check if create-dmg is available for a nicer DMG
if command -v create-dmg &>/dev/null; then
    rm -f "${APP_NAME}.dmg"
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 500 300 \
        --icon-size 80 \
        --icon "$APP_NAME.app" 150 150 \
        --app-drop-link 350 150 \
        "${APP_NAME}.dmg" \
        "$APP_NAME.app"
else
    # Fallback to hdiutil
    rm -f "${APP_NAME}.dmg"
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$APP_NAME.app" \
        -ov -format UDZO \
        "${APP_NAME}.dmg"
    echo "(Tip: brew install create-dmg for a nicer DMG with drag-to-Applications)"
fi

echo ""
echo "Created: ${APP_NAME}.dmg"
echo "Size: $(du -sh "${APP_NAME}.dmg" | cut -f1)"
