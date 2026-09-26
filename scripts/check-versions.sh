#!/bin/bash
# Fail unless the version in VERSION, Info.plist (CFBundleShortVersionString)
# and cli/package.json agree. When a release tag is given (first argument, or
# GITHUB_REF_NAME when it looks like vX.Y.Z), the tag must agree as well.
# A prerelease tag such as v4.0.0-rc.1 is accepted when its X.Y.Z part matches.
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

file_version="$(tr -d '[:space:]' < VERSION)"

if [ -x /usr/libexec/PlistBuddy ]; then
    plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
else
    plist_version="$(perl -0777 -ne 'print $1 if m{<key>CFBundleShortVersionString</key>\s*<string>([^<]*)</string>}' Info.plist)"
fi

if command -v node >/dev/null 2>&1; then
    cli_version="$(node -p 'require("./cli/package.json").version')"
else
    cli_version="$(perl -0777 -ne 'print $1 if m{^\{.*?"version"\s*:\s*"([^"]*)"}s' cli/package.json)"
fi

echo "VERSION file:      $file_version"
echo "Info.plist:        $plist_version"
echo "cli/package.json:  $cli_version"

if [ -z "$file_version" ]; then
    echo "error: VERSION file is empty" >&2
    fail=1
fi
if [ "$plist_version" != "$file_version" ]; then
    echo "error: Info.plist CFBundleShortVersionString ($plist_version) != VERSION ($file_version)" >&2
    fail=1
fi
if [ "$cli_version" != "$file_version" ]; then
    echo "error: cli/package.json version ($cli_version) != VERSION ($file_version)" >&2
    fail=1
fi

tag="${1:-}"
if [ -z "$tag" ] && [[ "${GITHUB_REF_NAME:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    tag="$GITHUB_REF_NAME"
fi

if [ -n "$tag" ]; then
    tag_version="${tag#v}"
    tag_base="${tag_version%%-*}"
    echo "Tag:               $tag"
    if [ "$tag_version" != "$file_version" ] && [ "$tag_base" != "$file_version" ]; then
        echo "error: tag $tag does not match VERSION ($file_version)" >&2
        fail=1
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "Version check failed. Run scripts/bump-version.sh X.Y.Z to realign." >&2
    exit 1
fi
echo "Versions agree."
