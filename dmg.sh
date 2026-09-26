#!/bin/bash
# Build a DMG containing Prune.app and an /Applications drop link.
#
# Environment:
#   APP_DIR   directory that contains Prune.app (default: dist)
#   DMG_NAME  file name of the DMG, written into APP_DIR (default: Prune.dmg)
#
# Uses create-dmg (brew install create-dmg) when available for a styled
# window; falls back to hdiutil otherwise. On CI (CI=true) create-dmg runs
# with --skip-jenkins because Finder scripting is unreliable on headless
# runners.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Prune"
APP_DIR="${APP_DIR:-dist}"
DMG_NAME="${DMG_NAME:-${APP_NAME}.dmg}"
APP_PATH="$APP_DIR/$APP_NAME.app"
DMG_PATH="$APP_DIR/$DMG_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "error: '$APP_PATH' not found. Run ./build.sh first." >&2
    exit 1
fi

# Both tools copy the contents of a source folder into the volume root, so
# stage the app in its own folder instead of passing the .app directly.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/prune-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"

rm -f "$DMG_PATH"
echo "Creating $DMG_PATH..."

if command -v create-dmg >/dev/null 2>&1; then
    extra_args=()
    if [ "${CI:-}" = "true" ]; then
        extra_args+=(--skip-jenkins)
    fi
    create-dmg \
        --volname "$APP_NAME" \
        --window-size 500 300 \
        --icon-size 80 \
        --icon "$APP_NAME.app" 150 150 \
        --app-drop-link 350 150 \
        --hdiutil-retries 10 \
        "${extra_args[@]+"${extra_args[@]}"}" \
        "$DMG_PATH" \
        "$STAGING"
else
    ln -s /Applications "$STAGING/Applications"
    # hdiutil occasionally fails with "Resource busy" on CI runners; retry.
    attempt=1
    until hdiutil create -volname "$APP_NAME" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"; do
        if [ "$attempt" -ge 5 ]; then
            echo "error: hdiutil create failed after $attempt attempts" >&2
            exit 1
        fi
        attempt=$((attempt + 1))
        echo "hdiutil create failed, retrying ($attempt/5)..." >&2
        sleep 3
    done
    echo "(Tip: brew install create-dmg for a styled DMG window)"
fi

echo "Created: $DMG_PATH ($(du -sh "$DMG_PATH" | cut -f1))"
