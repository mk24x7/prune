#!/bin/bash
# Package a built Prune.app into release artifacts.
#
# Environment:
#   VERSION      release version used in artifact names (default: VERSION file)
#   OUT_DIR      directory that contains Prune.app and receives the artifacts
#                (default: dist)
#   ALLOW_THIN   set to 1 to package a single-architecture app (local testing);
#                by default the app must contain both arm64 and x86_64
#
# Produces, in OUT_DIR:
#   Prune-$VERSION-macos-universal.zip
#   Prune-$VERSION-macos-universal.dmg
#   SHA256SUMS.txt
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
OUT_DIR="${OUT_DIR:-dist}"
APP_PATH="$OUT_DIR/Prune.app"
BASE_NAME="Prune-$VERSION-macos-universal"
ZIP_NAME="$BASE_NAME.zip"
DMG_NAME="$BASE_NAME.dmg"

if [ -z "$VERSION" ]; then
    echo "error: VERSION is empty" >&2
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "error: '$APP_PATH' not found. Run ./build.sh first." >&2
    exit 1
fi

BINARY="$APP_PATH/Contents/MacOS/Prune"
ARCHS_FOUND="$(lipo -archs "$BINARY")"
echo "Architectures: $ARCHS_FOUND"
for arch in arm64 x86_64; do
    case " $ARCHS_FOUND " in
        *" $arch "*) ;;
        *)
            if [ "${ALLOW_THIN:-0}" != "1" ]; then
                echo "error: $BINARY lacks $arch; build with ARCHS=\"arm64 x86_64\" or set ALLOW_THIN=1" >&2
                exit 1
            fi
            echo "warning: $BINARY lacks $arch (ALLOW_THIN=1)" >&2
            ;;
    esac
done

codesign --verify --deep --strict "$APP_PATH"

rm -f "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$DMG_NAME" "$OUT_DIR/SHA256SUMS.txt"

echo "Creating $OUT_DIR/$ZIP_NAME..."
ditto -c -k --keepParent "$APP_PATH" "$OUT_DIR/$ZIP_NAME"

APP_DIR="$OUT_DIR" DMG_NAME="$DMG_NAME" ./dmg.sh

(
    cd "$OUT_DIR"
    shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > SHA256SUMS.txt
    echo ""
    echo "SHA256SUMS.txt:"
    /bin/cat SHA256SUMS.txt
)
