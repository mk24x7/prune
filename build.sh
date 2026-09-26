#!/bin/bash
# Build Prune.app from source and ad-hoc sign it.
#
# Environment:
#   VERSION        marketing version written to the bundle
#                  (default: exact git tag on HEAD without the v, else the VERSION file)
#   BUILD_NUMBER   CFBundleVersion (default: git commit count, then 1)
#   ARCHS          space-separated architectures, e.g. "arm64 x86_64"
#                  (default: the current machine)
#   OUT_DIR        output directory; the app is assembled at $OUT_DIR/Prune.app
#                  (default: dist)
#   SWIFT_FLAGS    extra flags for swift build, e.g. --disable-sandbox
#   SIGN_IDENTITY  codesign identity (default: "-" for ad-hoc)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Prune"
RESOURCE_BUNDLE="Prune_PruneDefinitions.bundle"

# Prefer an exact tag on HEAD (release builds), otherwise the VERSION file.
if [ -z "${VERSION:-}" ]; then
    VERSION="$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)"
fi
if [ -z "${VERSION:-}" ] && [ -f VERSION ]; then
    VERSION="$(tr -d '[:space:]' < VERSION)"
fi
if [ -z "${VERSION:-}" ]; then
    echo "error: VERSION could not be determined" >&2
    exit 1
fi
if [ -z "${BUILD_NUMBER:-}" ]; then
    BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
fi
ARCHS="${ARCHS:-$(uname -m)}"
OUT_DIR="${OUT_DIR:-dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"

# shellcheck disable=SC2206
SWIFT_EXTRA=(${SWIFT_FLAGS:-})

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) for: $ARCHS"

BINARIES=()
FIRST_BIN_DIR=""
for arch in $ARCHS; do
    triple="$arch-apple-macosx"
    echo "swift build -c release --triple $triple ${SWIFT_EXTRA[*]:-}"
    swift build -c release --triple "$triple" ${SWIFT_EXTRA[@]+"${SWIFT_EXTRA[@]}"}
    bin_dir="$(swift build -c release --triple "$triple" ${SWIFT_EXTRA[@]+"${SWIFT_EXTRA[@]}"} --show-bin-path)"
    BINARIES+=("$bin_dir/$APP_NAME")
    if [ -z "$FIRST_BIN_DIR" ]; then
        FIRST_BIN_DIR="$bin_dir"
    fi
done

echo "Assembling $APP_BUNDLE..."
mkdir -p "$OUT_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

if [ "${#BINARIES[@]}" -gt 1 ]; then
    lipo -create "${BINARIES[@]}" -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
else
    cp "${BINARIES[0]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

# The SwiftPM resource bundle carries artifacts.json. The app looks for it in
# Contents/Resources (see Definitions/PruneDefinitions.swift).
if [ ! -d "$FIRST_BIN_DIR/$RESOURCE_BUNDLE" ]; then
    echo "error: $FIRST_BIN_DIR/$RESOURCE_BUNDLE was not produced by swift build" >&2
    exit 1
fi
cp -R "$FIRST_BIN_DIR/$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
if [ ! -f "$APP_BUNDLE/Contents/Resources/$RESOURCE_BUNDLE/artifacts.json" ]; then
    echo "error: artifacts.json is missing from the assembled bundle" >&2
    exit 1
fi

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "Signing with identity: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo "Architectures: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
echo "Size: $(du -sh "$APP_BUNDLE" | cut -f1)"
echo ""
echo "Next: ./package.sh (zip, dmg, checksums) or APP_DIR=$OUT_DIR ./dmg.sh"
